#!/bin/sh
# ==============================================================================
# MODULE : INITIALISATION ELASTICSEARCH (USER SETUP)
# ==============================================================================
# DESCRIPTION :
#   Ce script configure les mots de passe des utilisateurs systèmes (Built-in)
#   d'Elasticsearch.
#
# CONTEXTE :
#   Par défaut, Elasticsearch initialise le compte 'elastic' (superuser).
#   Cependant, Kibana nécessite un utilisateur technique spécifique ('kibana_system')
#   pour fonctionner et se connecter au cluster de monitoring.
#
# OBJECTIFS :
#   1. Attendre la disponibilité du cluster Elasticsearch (Healthcheck).
#   2. Utiliser le compte 'elastic' (admin) pour définir le mot de passe de
#      l'utilisateur 'kibana_system'.
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
# Le fichier logger.sh est injecté dans le même volume (/scripts) via la ConfigMap.
if [ -f /scripts/logger.sh ]; then
    # Note : Sur Alpine (sh), la commande 'source' peut être absente, on utilise '.'
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
if [ -f /vault/secrets/elastic ] && [ -f /vault/secrets/kibana ]; then
    . /vault/secrets/elastic
    . /vault/secrets/kibana
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

log_success "Secrets chargés en mémoire."

# ==============================================================================
# 3. VÉRIFICATION DE LA DISPONIBILITÉ (HEALTHCHECK)
# ==============================================================================

log_step "Connexion au cluster Elasticsearch ($ES_HOST)..."

# Boucle d'attente active (Retry Pattern)
# On attend que le statut du cluster soit 'green' ou 'yellow'.
# Note : 'yellow' est l'état normal pour un cluster single-node (replicas non assignés).
until curl -s -u "elastic:$ELASTIC_PASSWORD" "$ES_HOST/_cluster/health" | grep -q '"status":"green"\|"status":"yellow"'; do
    log_warn "Cluster indisponible ou en cours d'initialisation. Nouvelle tentative dans ${RETRY_DELAY}s..."
    sleep $RETRY_DELAY
done

log_success "Connexion établie : Le cluster Elasticsearch est opérationnel."

# ==============================================================================
# 4. CONFIGURATION DES COMPTES SYSTÈMES
# ==============================================================================

log_step "Configuration de l'utilisateur technique 'kibana_system'..."

# Appel API à l'endpoint de sécurité native (_security)
# On utilise curl en mode silencieux (-s) mais on capture le code HTTP (-w)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
  -u "elastic:$ELASTIC_PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"$KIBANA_SYSTEM_PASSWORD\"}" \
  "$ES_HOST/_security/user/kibana_system/_password")

if [ "$HTTP_CODE" -eq 200 ]; then
    log_success "Le mot de passe de 'kibana_system' a été mis à jour avec succès."
    
    # Message de fin pour les logs du Job Kubernetes
    echo ""
    log_info "Initialisation terminée. Le Job va s'arrêter."
    exit 0
else
    log_error "Échec critique lors de la mise à jour du mot de passe."
    log_error "Code réponse HTTP : $HTTP_CODE"
    log_error "Vérifiez les logs Elasticsearch pour plus de détails."
    exit 1
fi