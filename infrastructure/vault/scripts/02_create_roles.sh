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
# 2. DÉFINITION DE LA FONCTION DE CRÉATION
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
# 3. APPLICATION DES RÔLES
# ==============================================================================

# A. INFRASTRUCTURE ------------------------------------------------------------

# RabbitMQ : Accès aux identifiants admin et cookie Erlang
create_role "rabbitmq-role" "rabbitmq-policy" "rabbitmq"

# Elasticsearch : Accès "root" pour l'initialisation du cluster
create_role "elastic-role" "elastic-policy" "elasticsearch"

# Kibana : Accès à sa propre config ET au cluster Elastic (monitoring/setup)
create_role "kibana-role" "kibana-policy" "kibana"

# Logstash : Droit d'écriture (ingestion) dans Elastic
create_role "logstash-role" "logstash-policy" "logstash"

# B. APPLICATIONS --------------------------------------------------------------

# API Gateway : Accès aux secrets partagés (JWT, Env, Ports)
create_role "gateway-role" "gateway-policy" "gateway"

# Note : De nouveaux rôles (ex: auth-service, user-service) devront être ajoutés
# ici au fur et à mesure du développement des microservices.

log_info "Tous les rôles ont été configurés avec succès."