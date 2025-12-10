#!/bin/bash
# ==============================================================================
# MODULE 00 : AUTHENTIFICATION KUBERNETES
# ==============================================================================
# DESCRIPTION :
#   Ce script configure la méthode d'authentification "Kubernetes" dans Vault.
#   Cette étape est cruciale car elle permet aux pods de s'authentifier auprès
#   de Vault en utilisant leur propre ServiceAccount (JWT), sans avoir besoin
#   de manipuler des tokens Vault manuellement.
#
# ACTIONS :
#   1. Activer le moteur d'auth 'kubernetes/' si nécessaire.
#   2. Configurer le lien avec l'API Server interne de Kubernetes.
# ==============================================================================

# Arrêt immédiat en cas d'erreur
set -e

# ==============================================================================
# 1. CONTRÔLE DE L'ENVIRONNEMENT
# ==============================================================================

# Vérification défensive : Les fonctions de logging sont-elles disponibles ?
if ! declare -F log_info > /dev/null; then
    echo "Erreur : Ce script doit être lancé via l'orchestrateur init.sh"
    exit 1
fi

log_info "Démarrage du module de connexion Kubernetes..."

# ==============================================================================
# 2. ACTIVATION DU MOTEUR D'AUTHENTIFICATION
# ==============================================================================

# On vérifie d'abord si la méthode est déjà active pour éviter une erreur
# Le grep cherche "kubernetes/" dans la liste des méthodes montées
if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault auth list" | grep -q "kubernetes/"; then
    log_info "Méthode d'authentification 'kubernetes' déjà active. (Skip)"
else
    log_warn "Activation du moteur d'authentification 'kubernetes'..."
    
    if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault auth enable kubernetes" > /dev/null 2>&1; then
        log_success "Moteur 'kubernetes' activé avec succès."
    else
        log_error "Échec de l'activation de l'authentification Kubernetes."
        exit 1
    fi
fi

# ==============================================================================
# 3. CONFIGURATION DE LA CONNEXION (API SERVER)
# ==============================================================================

log_info "Configuration du lien technique Vault <-> K8s API..."

# EXPLICATION TECHNIQUE :
# Vault doit vérifier la validité des tokens JWT envoyés par les pods.
# Pour cela, il a besoin de contacter l'API Server Kubernetes.
# Nous configurons Vault pour qu'il utilise :
# - L'adresse interne du cluster (https://kubernetes.default.svc:443)
# - Le certificat CA du cluster (injecté par défaut dans le pod Vault)
# - Le token du ServiceAccount du pod Vault lui-même (token_reviewer_jwt)

# Note : disable_iss_validation=true est souvent requis sur les clusters dev/k3s
# où l'issuer du JWT peut varier légèrement.

if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/config \
    kubernetes_host='https://kubernetes.default.svc:443' \
    disable_iss_validation=true \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
    token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token" > /dev/null 2>&1; then
    
    log_success "Configuration de l'API Kubernetes appliquée."
else
    log_error "Impossible de configurer la liaison avec l'API Kubernetes."
    exit 1
fi