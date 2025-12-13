#!/bin/bash
# ==============================================================================
# MODULE 02 : GESTION DES RÔLES (RBAC)
# ==============================================================================
# DESCRIPTION :
#   Ce script configure les rôles d'authentification Kubernetes dans Vault.
#   Un "Rôle" fait le lien entre une identité Kubernetes (ServiceAccount) et
#   une ou plusieurs politiques Vault (Policies).
#
# PRINCIPE DE FONCTIONNEMENT :
#   1. Le Pod s'authentifie avec son Token JWT (ServiceAccount).
#   2. Vault vérifie la validité du JWT auprès de l'API Server K8s.
#   3. Vault vérifie si ce ServiceAccount est autorisé par un Rôle spécifique.
#   4. Si oui, Vault délivre un token hébergeant les politiques associées.
# ==============================================================================

# Arrêt immédiat en cas d'erreur
set -e

# ==============================================================================
# 1. CONTRÔLE DE L'ENVIRONNEMENT
# ==============================================================================

if ! declare -F log_info > /dev/null; then
    echo "Erreur : Ce script doit être lancé via l'orchestrateur init.sh"
    exit 1
fi

log_info "Démarrage du module de gestion des Rôles (Role Binding)..."

# ==============================================================================
# 2. CONFIGURATION DES RÔLES
# ==============================================================================

# Liste des rôles à créer.
# Format : "NOM_DU_ROLE|POLITIQUES_SEPAREES_PAR_VIRGULES|SERVICE_ACCOUNT_K8S"
#
# Changements de sécurité (Kibana) :
# - kibana-role : Accès restreint uniquement à la configuration Kibana (Runtime).
# - elastic-admin-init-role : Rôle privilégié pour le Job d'initialisation, 
#   cumulant l'accès root Elastic et l'accès système Kibana.

ROLES_LIST=(
    # --- INFRASTRUCTURE DE MESSAGERIE & DONNÉES ---
    "rabbitmq-role|rabbitmq-policy|rabbitmq"
    "elastic-role|elastic-policy|elasticsearch"
    "logstash-role|logstash-policy|logstash"

    # --- KIBANA & MONITORING ---
    # Runtime Application : Moindre privilège
    "kibana-role|kibana-policy|kibana"
    # Maintenance & Setup : Privilèges élevés (Root Elastic + System Kibana)
    "elastic-admin-init-role|elastic-policy,kibana-policy,logstash-policy|elastic-admin-init"

    # --- APPLICATIONS BACKEND ---
    "gateway-role|gateway-policy|gateway"
    "service-template-role|service-template-policy|service-template"
)

# ==============================================================================
# 3. DÉFINITION DE LA FONCTION DE CRÉATION
# ==============================================================================

# Fonction générique pour créer ou mettre à jour un rôle
create_role() {
    local role_name=$1    # Nom du rôle dans Vault
    local policy_name=$2  # Politique(s) à attacher (séparées par des virgules)
    local sa_name=$3      # Nom du ServiceAccount Kubernetes autorisé
    local namespace=${4:-default} # Namespace K8s (défaut: "default")
    local ttl="24h"       # Durée de vie du token généré

    log_info "Configuration du rôle : $role_name"
    
    # EXPLICATION TECHNIQUE :
    # bound_service_account_names      : Liste blanche des SA autorisés.
    # bound_service_account_namespaces : Liste blanche des namespaces.
    # policies                         : Droits accordés.
    # ttl                              : Validité du token Vault délivré au pod.

    if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/role/$role_name \
        bound_service_account_names=$sa_name \
        bound_service_account_namespaces=$namespace \
        policies=$policy_name \
        ttl=$ttl" > /dev/null 2>&1; then
        
        log_success "Rôle '$role_name' lié au ServiceAccount '$sa_name' ($namespace)."
    else
        log_error "Échec de la création du rôle '$role_name'."
        exit 1
    fi
}

# ==============================================================================
# 4. APPLICATION DES RÔLES
# ==============================================================================

count=0

for role_config in "${ROLES_LIST[@]}"; do
    # Extraction des champs via le séparateur '|'
    IFS='|' read -r role_name policies sa_name <<< "$role_config"
    
    # Appel de la fonction de création
    # On trim les espaces éventuels pour la robustesse
    create_role "$(echo $role_name | xargs)" "$(echo $policies | xargs)" "$(echo $sa_name | xargs)"
    
    ((count+=1))
done

log_info "Total : $count rôle(s) configuré(s) avec succès."