#!/bin/bash
set -e

# Recuperation du Token Root depuis le .env pour s'authentifier dans le script
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

generate_key_32() {
  # Génère 32 caractères
  openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c 32
}

echo "Configuration de Vault pour Kubernetes..."

# 1. Attente que Vault soit prêt (Healthcheck basique)
echo "   -> En attente du pod vault-0..."
kubectl wait --for=condition=Ready pod/vault-0 --timeout=60s

echo "VAULT_TOKEN=${VAULT_ROOT_TOKEN}"

# 2. Activation de l'auth Kubernetes
# On utilise le Token Root injecté via Helm pour effectuer ces opérations administratives
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault auth enable kubernetes"

# 3. Configuration du lien Vault <-> API Kubernetes
# Vault utilise le ServiceAccount local (monté dans le pod) pour parler à l'API K8s
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/config \
    kubernetes_host='https://\$KUBERNETES_PORT_443_TCP_ADDR:443' \
    token_reviewer_jwt='\$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)' \
    kubernetes_ca_cert='\$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)' \
    issuer='https://kubernetes.default.svc.cluster.local'"

echo "🔧 Création des Politiques (Policies) granulaires..."

# --- 1. RABBITMQ POLICY ---
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write rabbitmq-policy - <<EOF
path \"secret/data/infra/rabbitmq\" {
  capabilities = [\"read\"]
}
EOF"

# --- 2. ELASTICSEARCH POLICY ---
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write elastic-policy - <<EOF
path \"secret/data/infra/elastic\" {
  capabilities = [\"read\"]
}
EOF"

# --- 3. KIBANA POLICY (Besoin de ses clés ET du password elastic) ---
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write kibana-policy - <<EOF
path \"secret/data/infra/kibana\" {
  capabilities = [\"read\"]
}
path \"secret/data/infra/elastic\" {
  capabilities = [\"read\"]
}
EOF"

# --- 4. LOGSTASH POLICY (Besoin du password elastic pour l'output) ---
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write logstash-policy - <<EOF
path \"secret/data/infra/elastic\" {
  capabilities = [\"read\"]
}
EOF"

# --- 5. GATEWAY POLICY ---
kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write gateway-policy - <<EOF
path \"secret/data/app/common\" {
  capabilities = [\"read\"]
}
EOF"

echo "🔧 Création des Rôles Kubernetes..."

# Fonction helper pour créer un rôle
create_role() {
    local role_name=$1
    local policy_name=$2
    echo "   -> Role: $role_name"
    kubectl exec vault-0 -- /bin/sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write auth/kubernetes/role/$role_name \
        bound_service_account_names=default \
        bound_service_account_namespaces=default \
        policies=$policy_name \
        ttl=24h"
}

create_role "rabbitmq-role" "rabbitmq-policy"
create_role "elastic-role" "elastic-policy"
create_role "kibana-role" "kibana-policy"
create_role "logstash-role" "logstash-policy"
create_role "gateway-role" "gateway-policy"

# ==============================================================================
# 6. GÉNÉRATION ET INJECTION DES SECRETS (ZERO TRUST)
# ==============================================================================
echo "Génération et injection des secrets dynamiques..."

# Génération en mémoire
RABBITMQ_PASS=$(generate_key_32)
ELASTIC_PASS=$(generate_key_32)
KIBANA_ENC_KEY=$(generate_key_32)
JWT_SECRET=$(generate_key_32)

echo "Injection des secrets d'infrastructure dans Vault..."
# Injection RabbitMQ
kubectl exec vault-0 -- vault kv put secret/infra/rabbitmq \
    user="${RABBITMQ_USER}" \
    password="${RABBITMQ_PASS}"

# Injection Elastic
kubectl exec vault-0 -- vault kv put secret/infra/elastic \
    password="${ELASTIC_PASS}"

# Injection Kibana
kubectl exec vault-0 -- vault kv put secret/infra/kibana \
    encryption_key="${KIBANA_ENC_KEY}"

# Injection App Common (Exemple)
kubectl exec vault-0 -- vault kv put secret/app/common \
    jwt_secret="${JWT_SECRET}" \
    node_env="${NODE_ENV}"

echo "Vault est configuré. Les secrets ont été générés aléatoirement."
echo "   -> Pour voir les secrets générés (Debug): kubectl exec vault-0 -- sh -c 'VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault kv get secret/infra/rabbitmq'"