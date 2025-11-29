#!/bin/bash
set -e

# 1. Chargement des secrets pour le processus principal (Elasticsearch)
export ELASTIC_PASSWORD=$(cat /shared/secrets/elastic_password)

# 2. Fonction d'auto-configuration (exécutée en arrière-plan)
configure_kibana_user() {
  echo "[Elasticsearch Entrypoint] En attente du démarrage d'Elasticsearch..."
  until curl -s -f -u elastic:${ELASTIC_PASSWORD} http://localhost:9200/_cluster/health > /dev/null; do
    sleep 2
  done

  echo "[Elasticsearch Entrypoint] Elasticsearch est prêt. Configuration du mot de passe 'kibana_system'..."
  KIBANA_SYS_PASS=$(cat /shared/secrets/kibana_system_password)

  response=$(curl -s -o /dev/null -w "%{http_code}" -u elastic:${ELASTIC_PASSWORD} \
    -X POST http://localhost:9200/_security/user/kibana_system/_password \
    -H 'Content-Type: application/json' \
    -d "{\"password\":\"${KIBANA_SYS_PASS}\"}")

  if [ "$response" -eq 200 ]; then
    echo "[Elasticsearch Entrypoint] Mot de passe 'kibana_system' configuré avec succès."
  else
    echo "[Elasticsearch Entrypoint] ERREUR lors de la configuration du mot de passe ($response)."
  fi
}

# Lancement de la configuration en arrière-plan (ne bloque pas le démarrage)
configure_kibana_user &

# 3. Démarrage du processus principal (remplace le shell actuel via exec)
# Cela garantit que Elasticsearch reçoit bien les signaux d'arrêt (PID 1)
exec /usr/local/bin/docker-entrypoint.sh eswrapper