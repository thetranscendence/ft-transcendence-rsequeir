#!/bin/bash
# ==============================================================================
# ORCHESTRATEUR D'INITIALISATION VAULT (MODE PERSISTANT)
# ==============================================================================
# DESCRIPTION :
#   Ce script est le point d'entrée unique pour le déploiement de la sécurité.
#   Il gère désormais le cycle de vie complet de Vault en production :
#   1. Initialisation (Génération des clés Master & Root Token).
#   2. Déverrouillage (Unseal) automatique via les clés stockées localement.
#   3. Configuration (Auth -> Policy -> Role -> PKI -> Secret).
#
# SÉCURITÉ :
#   Les clés de déverrouillage sont stockées dans 'cluster-keys.json'.
#   CE FICHIER NE DOIT JAMAIS ÊTRE COMMITÉ SUR GIT.
# ==============================================================================

# Arrêt immédiat en cas d'erreur critique
set -e

# ==============================================================================
# 1. CONFIGURATION DU CONTEXTE
# ==============================================================================

# Résolution des chemins absolus
BASE_DIR=$(dirname "$(realpath "$0")")
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGGER_SCRIPT="$BASE_DIR/../../scripts/logger.sh"
ENV_FILE="$BASE_DIR/../../.env"
KEYS_FILE="$BASE_DIR/../../cluster-keys.json" # Fichier sensible (ignoré par git)

# Chargement de l'utilitaire de logging
if [ -f "$LOGGER_SCRIPT" ]; then
    source "$LOGGER_SCRIPT"
    export -f log_header log_info log_success log_warn log_error log_step
else
    echo "Erreur critique : Utilitaire de logging introuvable ($LOGGER_SCRIPT)"
    exit 1
fi

log_header "INITIALISATION DE L'INFRASTRUCTURE ZERO TRUST (VAULT)"

# Vérification des dépendances locales
if ! command -v jq &> /dev/null; then
    log_error "L'outil 'jq' est requis pour le parsing JSON des clés Vault."
    log_error "Veuillez l'installer (ex: sudo apt install jq / brew install jq)."
    exit 1
fi

# ==============================================================================
# 2. CHARGEMENT DE L'ENVIRONNEMENT DE BASE
# ==============================================================================

if [ -f "$ENV_FILE" ]; then
    log_info "Chargement du contexte d'exécution depuis : .env"
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    log_warn "Fichier .env introuvable. Le script se basera sur les variables système."
fi

# ==============================================================================
# 3. HEALTHCHECK & ATTENTE DU SERVICE
# ==============================================================================

log_info "Vérification de la disponibilité du pod Vault (Timeout: 60s)..."

# On attend que le conteneur soit 'Running'. 
# Note : On ne vérifie pas 'Ready' car un Vault scellé n'est jamais 'Ready'.
if kubectl wait --for=condition=Initialized pod/vault-0 --timeout=60s > /dev/null 2>&1; then
    # Petite pause pour laisser le processus serveur démarrer
    sleep 5
    log_success "Pod Vault détecté."
else
    log_error "Le pod vault-0 ne répond pas."
    exit 1
fi

# ==============================================================================
# 4. GESTION DU CYCLE DE VIE (INIT & UNSEAL)
# ==============================================================================

log_step "Analyse du statut de Vault..."

# Récupération du statut au format JSON.
# '|| true' est nécessaire car vault status renvoie un code erreur si scellé.
VAULT_STATUS=$(kubectl exec vault-0 -- vault status -format=json 2>/dev/null || true)

# Extraction des états via jq
IS_INIT=$(echo "$VAULT_STATUS" | jq -r .initialized)
IS_SEALED=$(echo "$VAULT_STATUS" | jq -r .sealed)

# --- A. INITIALISATION (SI NÉCESSAIRE) ---
if [ "$IS_INIT" == "false" ]; then
    log_warn "Vault n'est pas initialisé. Démarrage de la procédure d'initialisation..."
    
    # Initialisation avec 1 clé de partage (Shamir) pour simplifier le stockage local.
    # Dans un vrai environnement Prod, on utiliserait -key-shares=5 -key-threshold=3
    if kubectl exec vault-0 -- vault operator init \
        -key-shares=1 \
        -key-threshold=1 \
        -format=json > "$KEYS_FILE"; then
        
        chmod 600 "$KEYS_FILE" # Protection des droits de lecture
        log_success "Vault initialisé avec succès."
        log_warn "CLÉS SAUVEGARDÉES DANS : $KEYS_FILE"
        log_warn "CE FICHIER EST CRITIQUE. NE LE PERDEZ PAS. NE LE COMMITEZ PAS."
        
        # Mise à jour du statut pour la suite
        IS_SEALED="true" 
    else
        log_error "Échec de l'initialisation de Vault."
        exit 1
    fi
else
    log_info "Vault est déjà initialisé."
fi

# --- B. DÉVERROUILLAGE (UNSEAL) ---
if [ "$IS_SEALED" == "true" ]; then
    log_warn "Vault est scellé. Tentative de déverrouillage..."
    
    if [ -f "$KEYS_FILE" ]; then
        # Extraction de la clé de déverrouillage (Unseal Key)
        UNSEAL_KEY=$(jq -r ".unseal_keys_b64[0]" "$KEYS_FILE")
        
        if kubectl exec vault-0 -- vault operator unseal "$UNSEAL_KEY" > /dev/null; then
            log_success "Vault déverrouillé et opérationnel."
        else
            log_error "La clé fournie n'a pas permis de déverrouiller Vault."
            exit 1
        fi
    else
        log_error "Vault est scellé mais le fichier '$KEYS_FILE' est introuvable."
        log_error "Impossible de récupérer la clé de déverrouillage."
        log_error "Solution : Si c'est une nouvelle installation, faites 'make fclean' pour repartir de zéro."
        exit 1
    fi
else
    log_success "Vault est déjà déverrouillé."
fi

# --- C. EXPORT DU ROOT TOKEN ---
# Pour configurer Vault, nous avons besoin du Root Token.
# En mode persistant, il est dans notre fichier JSON, pas dans le .env.

if [ -f "$KEYS_FILE" ]; then
    ROOT_TOKEN=$(jq -r ".root_token" "$KEYS_FILE")
    
    if [ -n "$ROOT_TOKEN" ] && [ "$ROOT_TOKEN" != "null" ]; then
        export VAULT_ROOT_TOKEN="$ROOT_TOKEN"
        log_info "Token Root chargé depuis le fichier de clés."
    fi
fi

if [ -z "$VAULT_ROOT_TOKEN" ]; then
    log_error "Aucun VAULT_ROOT_TOKEN disponible. Impossible de configurer l'infrastructure."
    exit 1
fi

# ==============================================================================
# 5. DÉFINITION DE LA PIPELINE DE CONFIGURATION
# ==============================================================================

# Liste ordonnée des modules
MODULES=(
    "00_connect_k8s.sh:Authentification Kubernetes (Auth Method)"
    "01_apply_policies.sh:Application des politiques de sécurité (ACLs)"
    "02_create_roles.sh:Création et liaison des rôles (RBAC)"
    "03_setup_pki.sh:Initialisation de la PKI (Certificats TLS)"
    "04_inject_secrets.sh:Génération et injection des secrets (Zero Trust)"
)

# ==============================================================================
# 6. EXÉCUTION DES MODULES
# ==============================================================================

run_module() {
    local script_name=$1
    local description=$2
    local full_path="$SCRIPTS_DIR/$script_name"

    log_step "Module : $description"

    if [ -f "$full_path" ]; then
        # Exécution dans un sous-processus Bash avec le Token exporté
        bash "$full_path"
    else
        log_error "Fichier module introuvable : $full_path"
        exit 1
    fi
}

for module in "${MODULES[@]}"; do
    script_name="${module%%:*}"
    description="${module#*:}"
    run_module "$script_name" "$description"
done

# ==============================================================================
# 7. CLÔTURE
# ==============================================================================

log_success "Infrastructure de sécurité configurée avec persistance."
log_info "Vault est prêt à servir les secrets."