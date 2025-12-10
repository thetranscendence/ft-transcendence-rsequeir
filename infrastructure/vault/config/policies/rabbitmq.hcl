# ==============================================================================
# POLITIQUE DE SÉCURITÉ : SERVICE RABBITMQ
# ==============================================================================
# DESCRIPTION :
#   Cette politique définit les permissions minimales (Least Privilege) requises
#   pour le déploiement du broker de messages RabbitMQ au sein du cluster.
#
# CONSOMMATEUR :
#   - Role Vault : rabbitmq-role
#   - ServiceAccount K8s : rabbitmq (namespace: default)
#
# USAGE :
#   Utilisé par le "Vault Agent Sidecar" injecté dans le Pod RabbitMQ pour
#   récupérer les identifiants administrateur générés dynamiquement et
#   configurer les variables d'environnement au démarrage.
# ==============================================================================

# Accès en lecture aux secrets d'infrastructure RabbitMQ.
#
# NOTE IMPORTANTE SUR LE CHEMIN (KV Version 2) :
# Le segment "/data/" est impératif pour accéder aux données dans un moteur
# de secrets versionné (KV-v2).
# - Chemin logique (CLI) : secret/infra/rabbitmq
# - Chemin physique (Policy) : secret/data/infra/rabbitmq
#
# DONNÉES ACCESSIBLES :
# - user : Nom d'utilisateur admin (ex: guest)
# - password : Mot de passe fort généré par le script d'initialisation
path "secret/data/infra/rabbitmq" {
  capabilities = ["read"]
}