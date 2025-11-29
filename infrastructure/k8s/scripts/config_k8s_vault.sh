#!/bin/bash

# 1. Activer l'auth Kubernetes dans Vault
# On utilise kubectl exec pour lancer les commandes CLI directement dans le pod Vault
kubectl exec vault-0 -- vault auth enable kubernetes

# 2. Configurer le lien Vault <-> Kubernetes API
kubectl exec vault-0 -- /bin/sh -c '
  vault write auth/kubernetes/config \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_ca_cert="$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)" \
    issuer="https://kubernetes.default.svc.cluster.local"
'

# 3. Créer la politique (policy) pour la Gateway
kubectl exec vault-0 -- /bin/sh -c '
  vault policy write backend-gateway-policy - <<EOF
  path "secret/data/app/common" {
    capabilities = ["read"]
  }
EOF
'

# 4. Créer le rôle qui lie le ServiceAccount K8s à cette politique
kubectl exec vault-0 -- vault write auth/kubernetes/role/backend-gateway-role \
    bound_service_account_names=default \
    bound_service_account_namespaces=default \
    policies=backend-gateway-policy \
    ttl=24h

echo "Vault configuré pour Kubernetes !"