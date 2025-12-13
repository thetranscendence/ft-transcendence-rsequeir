# ==============================================================================
# POLITIQUE DE SÉCURITÉ : SERVICE LOGSTASH (ETL)
# ==============================================================================
# DESCRIPTION :
#   Cette politique définit les permissions pour le service Logstash.
#   Elle applique le principe de moindre privilège en limitant l'accès
#   uniquement aux identifiants dédiés à l'écriture des logs.
#
# CONSOMMATEUR :
#   - Role Vault : logstash-role
#   - ServiceAccount K8s : logstash (namespace: default)
#
# USAGE :
#   Injecté via le "Vault Agent Sidecar" dans le Pod Logstash.
#   Ces secrets permettent de configurer l'output Elasticsearch dans le pipeline.
# ==============================================================================

# Accès en lecture aux identifiants spécifiques "Logstash Writer".
#
# CHANGEMENT DE SÉCURITÉ :
#   L'accès au compte "elastic" (superuser) a été révoqué.
#   Logstash utilise désormais un compte technique restreint ne possédant
#   que les droits d'ingestion (indexation).
#
# NOTE SUR LE CHEMIN (KV Version 2) :
#   - Chemin physique (Policy) : secret/data/infra/logstash
#   - Chemin logique (CLI)     : secret/infra/logstash
#
# DONNÉES ACCESSIBLES :
#   - username : Nom de l'utilisateur technique (ex: logstash_writer).
#   - password : Mot de passe associé généré par Vault.
path "secret/data/infra/logstash" {
  capabilities = ["read"]
}