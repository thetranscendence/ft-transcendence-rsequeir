#!/bin/bash
set -e

# Chargement du secret
export ELASTIC_PASSWORD=$(cat /shared/secrets/elastic_password)

# Démarrage de Logstash
exec /usr/local/bin/docker-entrypoint