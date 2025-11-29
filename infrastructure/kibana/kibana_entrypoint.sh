#!/bin/bash
set -e

# 1. Chargement des secrets pour Kibana
export ELASTICSEARCH_PASSWORD=$(cat /shared/secrets/kibana_system_password)
export XPACK_SECURITY_ENCRYPTIONKEY=$(cat /shared/secrets/kibana_encryption_key)
export XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=$(cat /shared/secrets/kibana_encryption_key)
export XPACK_REPORTING_ENCRYPTIONKEY=$(cat /shared/secrets/kibana_encryption_key)

# Pour la configuration API, on a besoin du mot de passe admin (elastic)
ADMIN_PASS=$(cat /shared/secrets/elastic_password)

# 2. Fonction de configuration du Data View
configure_dataview() {
  echo "[Kibana Entrypoint] En attente de l'API Kibana..."
  until curl -s -u elastic:${ADMIN_PASS} http://localhost:5601/api/status | grep -q '"level":"available"'; do
    sleep 5
  done

  echo "[Kibana Entrypoint] Kibana est prêt. Création du Data View..."
  curl -s -u elastic:${ADMIN_PASS} \
    -X POST http://localhost:5601/api/data_views/data_view \
    -H 'kbn-xsrf: true' \
    -H 'Content-Type: application/json' \
    -d '{"data_view":{"title":"ft_transcendence-*","name":"Transcendence Logs","timeFieldName":"@timestamp"}}'
  
  echo "[Kibana Entrypoint] Data View configuré."
}

# Lancement en arriège-plan
configure_dataview &

# 3. Démarrage de Kibana
exec /usr/local/bin/kibana-docker