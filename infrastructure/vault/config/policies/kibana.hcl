# ==============================================================================
# POLITIQUE DE SÉCURITÉ : SERVICE KIBANA (DASHBOARD)
# ==============================================================================
# DESCRIPTION :
#   Cette politique définit les accès nécessaires au fonctionnement de l'interface
#   Kibana.
#   Elle se limite strictement aux secrets propres à l'application Kibana
#   (clés de chiffrement et mot de passe système).
#
# CONSOMMATEUR :
#   - Role Vault : kibana-role
#   - ServiceAccount K8s : kibana (namespace: default)
#
# CAS D'USAGE SPÉCIFIQUE (JOB D'INITIALISATION) :
#   Cette politique est également attachée au Job "init-es-users" (via le rôle
#   "elastic-admin-init-role") pour lui permettre de lire le mot de passe
#   SYSTEM (infra/kibana) qu'il doit configurer dans Elasticsearch.
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration propre à Kibana
# ------------------------------------------------------------------------------
# DONNÉES ACCESSIBLES :
# - encryption_key : Clé utilisée pour chiffrer les "Saved Objects" (dashboards,
#                    visualisations) et les rapports dans la base interne.
# - password       : Le mot de passe de l'utilisateur technique "kibana_system".
#
# NOTE KV-V2 : Chemin physique 'secret/data/...' vs logique 'secret/...'
path "secret/data/infra/kibana" {
  capabilities = ["read"]
}