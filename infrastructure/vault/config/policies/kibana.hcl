# ==============================================================================
# POLITIQUE DE SÉCURITÉ : SERVICE KIBANA (DASHBOARD)
# ==============================================================================
# DESCRIPTION :
#   Cette politique définit les accès nécessaires au fonctionnement de l'interface
#   Kibana. Elle est particulière car elle agglomère les droits sur deux secrets
#   distincts pour permettre l'interconnexion avec Elasticsearch.
#
# CONSOMMATEUR :
#   - Role Vault : kibana-role
#   - ServiceAccount K8s : kibana (namespace: default)
#
# CAS D'USAGE SPÉCIFIQUE (JOB D'INITIALISATION) :
#   Cette politique est également utilisée par le Job "init-es-users" qui a besoin
#   de lire le mot de passe ROOT (infra/elastic) pour définir le mot de passe
#   SYSTEM (infra/kibana) via l'API Elasticsearch.
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Configuration propre à Kibana
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

# ------------------------------------------------------------------------------
# 2. Accès au Backend Elasticsearch
# ------------------------------------------------------------------------------
# POURQUOI ?
#   Kibana doit s'authentifier auprès d'Elasticsearch.
#   De plus, le script d'initialisation utilise ce token pour se connecter en
#   tant que super-utilisateur "elastic" afin de configurer les comptes systèmes.
#
# DONNÉES ACCESSIBLES :
# - password : Le mot de passe du super-utilisateur "elastic".
path "secret/data/infra/elastic" {
  capabilities = ["read"]
}