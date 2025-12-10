#!/bin/bash
# ==============================================================================
# ORCHESTRATEUR D'INITIALISATION VAULT
# ==============================================================================
# DESCRIPTION :
#   Ce script est le point d'entrée unique pour le déploiement de la sécurité.
#   Il orchestre l'exécution séquentielle des modules situés dans 'scripts/'.
#
# RESPONSABILITÉS :
#   1. Charger l'environnement et les outils de logging.
#   2. Vérifier la disponibilité du cluster et du service Vault.
#   3. Exécuter la chaîne de configuration (Auth -> Policy -> Role -> PKI -> Secret).
# ==============================================================================

# Arrêt immédiat en cas d'erreur critique
set -e

# ==============================================================================
# 1. CONFIGURATION DU CONTEXTE
# ==============================================================================

# Résolution des chemins absolus pour garantir l'exécution depuis n'importe où
BASE_DIR=$(dirname "$(realpath "$0")")
SCRIPTS_DIR="$BASE_DIR/scripts"
LOGGER_SCRIPT="$BASE_DIR/../../scripts/logger.sh"
ENV_FILE="$BASE_DIR/../../.env"

# Chargement de l'utilitaire de logging
if [ -f "$LOGGER_SCRIPT" ]; then
    source "$LOGGER_SCRIPT"
    # IMPORTANT : 'export -f' permet de rendre les fonctions de logging disponibles
    # dans les sous-shells créés par l'exécution des scripts modules.
    export -f log_header log_info log_success log_warn log_error log_step
else
    echo "Erreur critique : Utilitaire de logging introuvable ($LOGGER_SCRIPT)"
    exit 1
fi

log_header "INITIALISATION DE L'INFRASTRUCTURE ZERO TRUST (VAULT)"

# ==============================================================================
# 2. CHARGEMENT DE L'ENVIRONNEMENT
# ==============================================================================

if [ -f "$ENV_FILE" ]; then
    log_info "Chargement du contexte d'exécution depuis : .env"
    # Utilisation de grep/xargs pour nettoyer les commentaires et exporter proprement
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    log_warn "Fichier .env introuvable. Le script se basera sur les variables système."
fi

# Vérification de la clé de voûte de la sécurité
if [ -z "$VAULT_ROOT_TOKEN" ]; then
    log_error "La variable critique VAULT_ROOT_TOKEN est manquante."
    log_error "Action requise : Vérifiez votre fichier .env ou la configuration du Makefile."
    exit 1
fi

# ==============================================================================
# 3. HEALTHCHECK INFRASTRUCTURE
# ==============================================================================

log_info "Vérification de la disponibilité du service Vault (Timeout: 60s)..."

# On attend que le pod soit prêt à recevoir des requêtes API
if kubectl wait --for=condition=Ready pod/vault-0 --timeout=60s > /dev/null 2>&1; then
    log_success "Service Vault opérationnel et joignable."
else
    log_error "Échec du Healthcheck : Le pod vault-0 ne répond pas."
    exit 1
fi

# ==============================================================================
# 4. DÉFINITION DE LA PIPELINE DE CONFIGURATION
# ==============================================================================

# Liste ordonnée des modules.
# Syntaxe : "nom_du_script.sh:Description pour les logs"
MODULES=(
    "00_connect_k8s.sh:Authentification Kubernetes (Auth Method)"
    "01_apply_policies.sh:Application des politiques de sécurité (ACLs)"
    "02_create_roles.sh:Création et liaison des rôles (RBAC)"
    "03_setup_pki.sh:Initialisation de la PKI (Certificats TLS)"
    "04_inject_secrets.sh:Génération et injection des secrets (Zero Trust)"
)

# ==============================================================================
# 5. EXÉCUTION
# ==============================================================================

run_module() {
    local script_name=$1
    local description=$2
    local full_path="$SCRIPTS_DIR/$script_name"

    log_step "Démarrage du module : $description"

    if [ -f "$full_path" ]; then
        # Exécution dans un sous-processus Bash
        # Les fonctions de log sont héritées grâce à l'export -f précédent
        bash "$full_path"
    else
        log_error "Fichier module introuvable : $full_path"
        exit 1
    fi
}

# Boucle principale
for module in "${MODULES[@]}"; do
    # Extraction propre des champs via substitution de paramètres Bash
    # ${var%%:*} garde tout ce qui est AVANT le premier ":"
    # ${var#*:} garde tout ce qui est APRÈS le premier ":"
    script_name="${module%%:*}"
    description="${module#*:}"
    
    run_module "$script_name" "$description"
done

# ==============================================================================
# 6. CLÔTURE
# ==============================================================================

log_success "Configuration de l'infrastructure terminée avec succès."
log_info "Vault est prêt à servir les secrets aux applications."