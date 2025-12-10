# ==============================================================================
# POLITIQUE DE SÉCURITÉ : SERVICE ELASTICSEARCH
# ==============================================================================
# DESCRIPTION :
#   Cette politique accorde l'accès au secret "root" du cluster Elasticsearch.
#   Elle est utilisée par le nœud Elasticsearch lui-même pour s'initialiser,
#   mais aussi par d'autres services d'infrastructure (Kibana, Logstash) qui
#   ont besoin d'un accès privilégié ou de maintenance.
#
# CONSOMMATEURS :
#   1. Role Vault : elastic-role (ServiceAccount: elasticsearch)
#      -> Pour l'auto-configuration du nœud au démarrage.
#   2. Role Vault : kibana-role (ServiceAccount: kibana)
#      -> Pour que Kibana puisse se connecter et configurer les index systèmes.
#   3. Role Vault : logstash-role (ServiceAccount: logstash)
#      -> Pour l'écriture des logs dans les index.
#
# USAGE :
#   Injecté via le "Vault Agent Sidecar" pour définir la variable d'environnement
#   ELASTIC_PASSWORD requise par l'image Docker officielle.
# ==============================================================================

# Accès en lecture aux identifiants Superuser Elasticsearch.
#
# NOTE IMPORTANTE SUR LE CHEMIN (KV Version 2) :
# Le segment "/data/" est impératif pour accéder aux données dans un moteur
# de secrets versionné (KV-v2).
# - Chemin logique (CLI) : secret/infra/elastic
# - Chemin physique (Policy) : secret/data/infra/elastic
#
# DONNÉES ACCESSIBLES :
# - password : Le mot de passe du super-utilisateur par défaut "elastic".
#              Ce mot de passe est généré dynamiquement lors de l'initialisation.
path "secret/data/infra/elastic" {
  capabilities = ["read"]
}