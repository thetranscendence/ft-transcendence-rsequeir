# ==============================================================================
# POLITIQUE DE SÉCURITÉ : SERVICE LOGSTASH (ETL)
# ==============================================================================
# DESCRIPTION :
#   Cette politique permet au service Logstash d'accéder aux identifiants du
#   cluster Elasticsearch. C'est indispensable pour que le pipeline de traitement
#   puisse envoyer (indexer) les logs traités vers la base de données.
#
# CONSOMMATEUR :
#   - Role Vault : logstash-role
#   - ServiceAccount K8s : logstash (namespace: default)
#
# USAGE :
#   Injecté via le "Vault Agent Sidecar" dans le Pod Logstash.
#   Le secret est utilisé pour configurer l'authentification du plugin "output"
#   dans le fichier de pipeline (logstash.conf).
# ==============================================================================

# Accès en lecture aux crédentials Elasticsearch.
#
# POURQUOI ?
#   Logstash agit comme un "writer" dans le cluster Elastic. Il doit s'authentifier
#   pour avoir le droit d'écrire dans les index (ex: ft_transcendence-YYYY.MM.dd).
#   Dans cette configuration, il utilise le compte "elastic" (superuser).
#
# NOTE SUR LE CHEMIN (KV Version 2) :
#   L'ajout de "/data/" est requis pour les politiques KV-v2.
#   - Chemin physique (Policy) : secret/data/infra/elastic
#   - Chemin logique (CLI)     : secret/infra/elastic
#
# DONNÉES ACCESSIBLES :
#   - password : Le mot de passe du super-utilisateur "elastic".
path "secret/data/infra/elastic" {
  capabilities = ["read"]
}