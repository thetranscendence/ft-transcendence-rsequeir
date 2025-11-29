#!/bin/bash
set -e

# 1. Lire le mot de passe depuis le volume RAM sécurisé
RABBITMQ_PASS=$(cat /shared/secrets/rabbitmq_password)

# 2. Générer la configuration RabbitMQ
# On écrit dans le dossier conf.d pour que ce soit fusionné avec la config par défaut.
# Ce fichier écrase les utilisateurs/pass par défaut.
cat <<EOF > /etc/rabbitmq/conf.d/99-init-secrets.conf
default_user = ${RABBITMQ_DEFAULT_USER}
default_pass = ${RABBITMQ_PASS}
EOF

echo "[RabbitMQ Entrypoint] Configuration utilisateur '${RABBITMQ_DEFAULT_USER}' générée avec succès."

# 3. Lancer le point d'entrée officiel
exec docker-entrypoint.sh rabbitmq-server