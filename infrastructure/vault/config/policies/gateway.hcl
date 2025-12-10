# ==============================================================================
# POLITIQUE DE SÉCURITÉ : API GATEWAY (BACKEND)
# ==============================================================================
# DESCRIPTION :
#   Cette politique contrôle l'accès aux secrets pour le point d'entrée principal
#   du backend (API Gateway). Contrairement aux services d'infrastructure
#   (RabbitMQ, Elastic...), ce service consomme des secrets "applicatifs"
#   partagés.
#
# CONSOMMATEUR :
#   - Role Vault : gateway-role
#   - ServiceAccount K8s : gateway (namespace: default)
#
# USAGE :
#   Le Vault Agent Sidecar injecte ces secrets dans un fichier (ex: /vault/secrets/config)
#   qui est "sourcé" (. config) avant le démarrage du processus Node.js (Fastify).
# ==============================================================================

# Accès en lecture aux configurations applicatives partagées.
#
# CONTEXTE :
#   Ce chemin "app/common" regroupe les variables transversales nécessaires à
#   plusieurs microservices (Gateway, Auth, etc.) pour garantir la cohérence
#   cryptographique (même clé JWT) et environnementale.
#
# NOTE KV-V2 :
#   Le segment "/data/" est obligatoire dans la politique ACL.
#   - Chemin physique : secret/data/app/common
#   - Chemin logique  : secret/app/common
#
# DONNÉES ACCESSIBLES :
#   - jwt_secret : La clé secrète (symétrique) pour signer/vérifier les tokens JWT.
#   - node_env   : Le contexte d'exécution (development/production).
#   - api_port   : Le port d'écoute interne du container.
path "secret/data/app/common" {
  capabilities = ["read"]
}