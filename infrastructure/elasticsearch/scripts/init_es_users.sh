#!/bin/sh
# ==============================================================================
# MODULE : INITIALISATION ELASTICSEARCH (USER SETUP)
# ==============================================================================
# DESCRIPTION :
#   Ce script configure les mots de passe des utilisateurs systèmes (Built-in)
#   d'Elasticsearch et crée les utilisateurs techniques nécessaires (Logstash).
#
# CONTEXTE :
#   Par défaut, Elasticsearch initialise le compte 'elastic' (superuser).
#   Kibana nécessite un utilisateur technique 'kibana_system'.
#   Logstash nécessite un utilisateur 'writer' pour indexer les logs sans être root.
#
# OBJECTIFS :
#   1. Attendre la disponibilité du cluster Elasticsearch (Healthcheck).
#   2. Configurer le mot de passe de 'kibana_system'.
#   3. Créer/Mettre à jour l'utilisateur technique pour Logstash.
# ==============================================================================

# Arrêt immédiat en cas d'erreur (Fail-fast)
set -e

# Configuration
ES_HOST="http://elasticsearch:42920"
RETRY_DELAY=5

# ==============================================================================
# 1. CONTRÔLE DE L'ENVIRONNEMENT
# ==============================================================================

# Importation du logger partagé
if [ -f /scripts/logger.sh ]; then
    . /scripts/logger.sh
else
    echo "Erreur critique : Utilitaires de logging introuvables (/scripts/logger.sh)"
    exit 1
fi

log_header "INITIALISATION DES UTILISATEURS SYSTÈMES (ELASTIC)"

# ==============================================================================
# 2. CHARGEMENT DES SECRETS (ZERO TRUST)
# ==============================================================================

log_step "Chargement des identifiants injectés par Vault..."

# Les fichiers sont injectés par le Vault Agent Sidecar dans /vault/secrets/
if [ -f /vault/secrets/elastic ] && [ -f /vault/secrets/kibana ] && [ -f /vault/secrets/logstash ]; then
    . /vault/secrets/elastic
    . /vault/secrets/kibana
    . /vault/secrets/logstash
else
    log_error "Fichiers de secrets introuvables dans /vault/secrets/."
    exit 1
fi

# Validation défensive : On s'assure que les variables ont bien été exportées
if [ -z "$ELASTIC_PASSWORD" ]; then
    log_error "La variable ELASTIC_PASSWORD est vide ou manquante."
    exit 1
fi

if [ -z "$KIBANA_SYSTEM_PASSWORD" ]; then
    log_error "La variable KIBANA_SYSTEM_PASSWORD est vide ou manquante."
    exit 1
fi

if [ -z "$LOGSTASH_USER" ] || [ -z "$LOGSTASH_PASSWORD" ]; then
    log_error "Les identifiants LOGSTASH sont incomplets."
    exit 1
fi

log_success "Secrets chargés en mémoire."

# ==============================================================================
# 3. VÉRIFICATION DE LA DISPONIBILITÉ (HEALTHCHECK)
# ==============================================================================

log_step "Connexion au cluster Elasticsearch ($ES_HOST)..."

# Boucle d'attente active (Retry Pattern)
until curl -s -u "elastic:$ELASTIC_PASSWORD" "$ES_HOST/_cluster/health" | grep -q '"status":"green"\|"status":"yellow"'; do
    log_warn "Cluster indisponible ou en cours d'initialisation. Nouvelle tentative dans ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
done

log_success "Connexion établie : Le cluster Elasticsearch est opérationnel."

# ==============================================================================
# 4. CONFIGURATION DES COMPTES SYSTÈMES
# ==============================================================================

# --- A. KIBANA SYSTEM ---------------------------------------------------------
log_step "Configuration de l'utilisateur technique 'kibana_system'..."

HTTP_CODE_KIBANA=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -u "elastic:$ELASTIC_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$KIBANA_SYSTEM_PASSWORD\"}" \
  "$ES_HOST/_security/user/kibana_system/_password")

if [ "$HTTP_CODE_KIBANA" -eq 200 ]; then
    log_success "Le mot de passe de 'kibana_system' a été mis à jour avec succès."
else
    log_error "Échec critique lors de la mise à jour 'kibana_system'."
    log_error "Code réponse HTTP : $HTTP_CODE_KIBANA"
    exit 1
fi

# --- B. LOGSTASH WRITER (ROLE & USER) ---
log_step "Configuration du rôle et de l'utilisateur Logstash..."

# 1. Création du Rôle Personnalisé (Moindre Privilège)
#    On autorise la création et l'écriture UNIQUEMENT sur les index ft_transcendence-*
ROLE_PAYLOAD='{
  "cluster": ["monitor"],
  "indices": [
    {
      "names": ["ft_transcendence-*"],
      "privileges": ["write", "create_index", "index", "create", "auto_configure"]
    }
  ]
}'

HTTP_CODE_ROLE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -u "elastic:$ELASTIC_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "$ROLE_PAYLOAD" \
  "$ES_HOST/_security/role/logstash_writer_role")

if [ "$HTTP_CODE_ROLE" -eq 200 ] || [ "$HTTP_CODE_ROLE" -eq 201 ]; then
    log_success "Rôle 'logstash_writer_role' créé/mis à jour."
else
    log_error "Échec création rôle Logstash. Code: $HTTP_CODE_ROLE"
    exit 1
fi

# 2. Assignation du Rôle à l'utilisateur
USER_PAYLOAD="{\"password\":\"$LOGSTASH_PASSWORD\",\"roles\":[\"logstash_system\",\"logstash_writer_role\"],\"full_name\":\"Logstash Writer Service\"}"

HTTP_CODE_LOGSTASH=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -u "elastic:$ELASTIC_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "$USER_PAYLOAD" \
  "$ES_HOST/_security/user/$LOGSTASH_USER")

if [ "$HTTP_CODE_LOGSTASH" -eq 200 ] || [ "$HTTP_CODE_LOGSTASH" -eq 201 ]; then
    log_success "Utilisateur '${LOGSTASH_USER}' configuré avec succès."
    echo ""
    log_info "Initialisation terminée."
    exit 0
else
    log_error "Échec configuration utilisateur Logstash. Code: $HTTP_CODE_LOGSTASH"
    exit 1
fi