#!/bin/bash
# ==============================================================================
# MODULE 04 : INJECTION DES SECRETS (ZERO TRUST)
# ==============================================================================
# DESCRIPTION :
#   Ce script génère et injecte les secrets d'infrastructure et d'application
#   dans le moteur Key-Value (KV v2) de Vault.
#
# PRINCIPES CLÉS :
#   1. Aléatoire fort : Utilisation d'OpenSSL pour générer les mots de passe.
#   2. Idempotence : Si un secret critique existe déjà, il n'est PAS écrasé.
#      Cela évite de désynchroniser l'application et la base de données (PVC).
#   3. Mise à jour Config : Les variables non-sensibles (NODE_ENV, Ports) sont
#      mises à jour à chaque exécution via 'vault kv patch'.
# ==============================================================================

# Arrêt immédiat en cas d'erreur
set -e

# ==============================================================================
# 1. CONTRÔLE DE L'ENVIRONNEMENT
# ==============================================================================

if ! declare -F log_info > /dev/null; then
    echo "❌ Erreur : Ce script doit être lancé via l'orchestrateur init.sh"
    exit 1
fi

log_info "Démarrage du module de gestion des secrets..."

# ==============================================================================
# 2. FONCTIONS UTILITAIRES
# ==============================================================================

# Génère une chaîne aléatoire alphanumérique de 32 caractères
generate_pwd() {
    openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32
}

# Vérifie si une clé spécifique existe dans un chemin Vault
# Retourne 0 (Vrai) si la clé existe, 1 (Faux) sinon.
secret_exists() {
    local path=$1
    local key=$2
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv get -field=$key $path" > /dev/null 2>&1
}

# ==============================================================================
# 3. GESTION DES SECRETS INFRASTRUCTURE
# ==============================================================================

# --- A. RABBITMQ --------------------------------------------------------------
# Nécessite : user, password
if secret_exists "secret/infra/rabbitmq" "password"; then
    log_info "Secrets RabbitMQ existants. (Conservation)"
else
    log_warn "Génération initiale des secrets RabbitMQ..."
    
    RABBIT_USER="${RABBITMQ_USER:-guest}"
    RABBIT_PASS=$(generate_pwd)
    
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv put secret/infra/rabbitmq \
        user='$RABBIT_USER' \
        password='$RABBIT_PASS'" > /dev/null
        
    log_success "Secrets RabbitMQ injectés."
fi

# --- B. ELASTICSEARCH ---------------------------------------------------------
# Nécessite : password (pour le superuser 'elastic')
if secret_exists "secret/infra/elastic" "password"; then
    log_info "Secrets Elasticsearch existants. (Conservation)"
else
    log_warn "Génération initiale des secrets Elasticsearch..."
    
    ELASTIC_PASS=$(generate_pwd)
    
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv put secret/infra/elastic \
        password='$ELASTIC_PASS'" > /dev/null
        
    log_success "Secrets Elasticsearch injectés."
fi

# --- C. KIBANA ----------------------------------------------------------------
# Nécessite : password (pour l'user système), encryption_key (pour les saved objects)
if secret_exists "secret/infra/kibana" "encryption_key"; then
    log_info "Secrets Kibana existants. (Conservation)"
else
    log_warn "Génération initiale des secrets Kibana..."
    
    # La clé de chiffrement doit être assez longue (32 chars min recommandés)
    KIBANA_ENC_KEY=$(generate_pwd)
    KIBANA_SYS_PASS=$(generate_pwd)
    
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv put secret/infra/kibana \
        encryption_key='$KIBANA_ENC_KEY' \
        password='$KIBANA_SYS_PASS'" > /dev/null
        
    log_success "Secrets Kibana injectés."
fi

# ==============================================================================
# 4. GESTION DES SECRETS APPLICATIFS (PARTAGÉS)
# ==============================================================================

# --- APP COMMON (Gateway, Auth, etc.) -----------------------------------------
# Nécessite : jwt_secret (Critique), node_env (Config), api_port (Config)

# Étape 1 : Gestion du secret JWT (Idempotent)
if secret_exists "secret/app/common" "jwt_secret"; then
    log_info "Clé de signature JWT existante. (Conservation)"
else
    log_warn "Génération de la clé de signature JWT..."
    JWT_SECRET=$(generate_pwd)
    
    # On utilise 'put' ici pour créer le secret initial s'il n'existe pas
    # ou pour ajouter le champ s'il manquait.
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv put secret/app/common \
        jwt_secret='$JWT_SECRET'" > /dev/null
        
    log_success "Clé JWT injectée."
fi

# Étape 2 : Mise à jour de la configuration (Toujours appliqué)
# On utilise 'patch' pour mettre à jour NODE_ENV et API_PORT sans toucher à jwt_secret
# Cela permet de changer d'environnement (dev -> prod) sans invalider les tokens utilisateurs.

CURRENT_ENV="${NODE_ENV:-development}"
CURRENT_PORT="${API_PORT:-3000}"

log_info "Mise à jour de la configuration applicative (Env: $CURRENT_ENV)..."

if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv patch secret/app/common \
    node_env='$CURRENT_ENV' \
    api_port='$CURRENT_PORT'" > /dev/null 2>&1; then
    
    log_success "Configuration 'app/common' synchronisée."
else
    # Fallback si le secret n'existait pas du tout (cas très rare vu l'étape 1)
    log_warn "Patch impossible, création du secret complet..."
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv put secret/app/common \
        node_env='$CURRENT_ENV' \
        api_port='$CURRENT_PORT'" > /dev/null
fi

log_info "Injection des secrets terminée."