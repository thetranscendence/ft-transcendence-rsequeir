#!/bin/sh
# ==============================================================================
# SCRIPT D'INITIALISATION AUTOMATISÉE DE L'INFRASTRUCTURE (BOOTSTRAP)
# ==============================================================================
# DESCRIPTION :
# Ce script est le point de départ de la chaîne de sécurité "Zero Trust".
# Il est exécuté par le conteneur éphémère 'vault-init' au lancement du cluster.
#
# RESPONSABILITÉS :
# 1. Attendre la disponibilité de l'API Vault.
# 2. Générer des secrets cryptographiquement forts (CSPRNG) pour l'infra.
# 3. Configurer le PKI interne pour le HTTPS (Certificats SSL).
# 4. Injecter les secrets dans Vault et les distribuer en mémoire (RAM) aux services.
# 5. Activer le moteur de chiffrement à la volée pour le GDPR.
#
# DÉPENDANCES :
# - vault (CLI)
# - jq (JSON Processor)
# - openssl (Génération d'entropie)
# ==============================================================================

# --- CONFIGURATION DE L'ENVIRONNEMENT ---
# L'adresse et le token sont injectés par Docker Compose
export VAULT_ADDR=http://vault:8200
export VAULT_TOKEN=${VAULT_ROOT_TOKEN}

# Chemins des volumes partagés
# CERTS_DIR   : Volume persistant ou partagé pour Nginx
# SECRETS_DIR : Volume temporaire (tmpfs/RAM) pour Postgres & RabbitMQ
CERTS_DIR="/shared/certs"
SECRETS_DIR="/shared/secrets"

# ------------------------------------------------------------------------------
# FONCTION : generate_password
# ------------------------------------------------------------------------------
# Génère une chaîne aléatoire de 20 caractères alphanumériques.
# Utilise OpenSSL pour garantir une entropie cryptographique suffisante,
# contrairement à $RANDOM qui est prévisible.
# ------------------------------------------------------------------------------
generate_password() {
  openssl rand -base64 24 | tr -dc 'a-zA-Z0-9' | head -c 20
}

# --- ATTENTE DE DISPONIBILITÉ DU SERVICE VAULT ---
echo "[Vault-Init] En attente de la disponibilité de l'API Vault..."
# Boucle d'attente active
until vault status > /dev/null 2>&1; do
  echo "  ... Vault inaccessible. Nouvelle tentative dans 2s."
  sleep 2
done
echo "[Vault-Init] Connexion établie avec succès !"

# ==============================================================================
# 1. GÉNÉRATION & DISTRIBUTION SÉCURISÉE DES SECRETS
# ==============================================================================
echo "[Vault-Init] Génération des identifiants d'infrastructure..."

# Création des secrets en mémoire
RABBITMQ_PASS=$(generate_password)
POSTGRES_PASS=$(generate_password)
JWT_SECRET=$(generate_password)

# Préparation du dossier de sortie
mkdir -p ${SECRETS_DIR}

# ÉCRITURE SUR DISQUE VIRTUEL (RAM)
# ⚠️ POINT CRITIQUE DE SÉCURITÉ :
# Ces fichiers sont écrits dans un volume monté en tmpfs (Mémoire Vive).
# Ils ne touchent JAMAIS le disque dur physique de l'hôte et disparaissent
# à l'extinction du conteneur.
echo -n "${RABBITMQ_PASS}" > ${SECRETS_DIR}/rabbitmq_password
echo -n "${POSTGRES_PASS}" > ${SECRETS_DIR}/postgres_password

# Restriction des droits (Lecture seule pour le propriétaire uniquement)
# Empêche tout autre utilisateur du conteneur de lire ces secrets.
chmod 600 ${SECRETS_DIR}/*_password

echo "[Vault-Init] Secrets écrits en RAM dans ${SECRETS_DIR}"

# ==============================================================================
# 2. CONFIGURATION MOTEUR PKI (INFRASTRUCTURE À CLÉ PUBLIQUE)
# ==============================================================================
# Vault agit comme notre Autorité de Certification (CA) interne.
# Cela permet d'avoir du HTTPS valide (cadenas vert) sur localhost sans alertes.
# ==============================================================================
if vault secrets list | grep -q "pki/"; then
    echo "[PKI] Moteur déjà activé."
else
    echo "[PKI] Initialisation de l'Autorité de Certification (CA)..."
    vault secrets enable pki
    # Augmentation du TTL par défaut à 1 an (8760h) pour éviter les expirations fréquentes en dev
    vault secrets tune -max-lease-ttl=8760h pki
    
    # Génération du certificat racine auto-signé
    echo "[PKI] Création du Root CA..."
    vault write -field=certificate pki/root/generate/internal \
      common_name="Transcendence Root CA" \
      ttl=8760h > ${CERTS_DIR}/root_ca.crt
    
    # Configuration des points de distribution (CRL/Issuing)
    vault write pki/config/urls \
      issuing_certificates="$VAULT_ADDR/v1/pki/ca" \
      crl_distribution_points="$VAULT_ADDR/v1/pki/crl"
fi

# Création d'un rôle permissif pour le développement
# Autorise la création de certificats pour 'localhost' et les sous-domaines
vault write pki/roles/transcendence-dot-local \
  allowed_domains="localhost,transcendence.localhost" \
  allow_subdomains=true \
  max_ttl=720h > /dev/null

# ÉMISSION DU CERTIFICAT SERVEUR (NGINX)
echo "[PKI] Génération dynamique du certificat SSL pour Nginx..."
vault write -format=json pki/issue/transcendence-dot-local \
  common_name="transcendence.localhost" \
  alt_names="localhost,api.transcendence.localhost" \
  ttl=720h > /tmp/nginx_cert.json

# Extraction et formatage via jq
# On concatène la clé publique du serveur avec celle du CA (Chain of Trust)
cat /tmp/nginx_cert.json | jq -r .data.certificate > ${CERTS_DIR}/transcendence.crt
cat /tmp/nginx_cert.json | jq -r .data.private_key > ${CERTS_DIR}/transcendence.key
cat /tmp/nginx_cert.json | jq -r .data.issuing_ca >> ${CERTS_DIR}/transcendence.crt

echo "[PKI] Certificats et clés exportés vers ${CERTS_DIR}"

# ==============================================================================
# 3. CONFIGURATION MOTEUR KV (KEY-VALUE STORE)
# ==============================================================================
# Centralisation des secrets pour l'application Backend (Fastify).
# Les microservices viendront lire ces secrets via l'API Vault au démarrage.
# ==============================================================================
if vault secrets list | grep -q "secret/"; then
    echo "[KV] Moteur déjà activé."
else
    echo "[KV] Activation du moteur de secrets KV v2..."
    vault secrets enable -path=secret kv-v2
fi

echo "[KV] Injection des secrets dans le coffre..."

# Secrets d'Infrastructure (lus par les services d'infra ou de monitoring)
vault kv put secret/infra/rabbitmq \
  user="${RABBITMQ_USER}" \
  password="${RABBITMQ_PASS}" \
  erlang_cookie="secret_cluster_cookie_fixed_for_dev"

vault kv put secret/infra/postgres \
  user="${POSTGRES_USER}" \
  password="${POSTGRES_PASS}" \
  db_name="transcendence"

# Secrets Applicatifs (Configuration globale partagée)
vault kv put secret/app/common \
  node_env="${NODE_ENV}" \
  jwt_secret="${JWT_SECRET}" \
  api_url="https://transcendence.localhost/api" \
  front_url="https://transcendence.localhost"

echo "[KV] Secrets injectés et versionnés."

# ==============================================================================
# 4. CONFIGURATION MOTEUR TRANSIT (DATA ENCRYPTION)
# ==============================================================================
# Module: GDPR & Privacy (V.6)
# Permet de chiffrer/déchiffrer les données personnelles (PII) à la volée
# sans que l'application ne stocke jamais la clé de chiffrement.
# ==============================================================================
if vault secrets list | grep -q "transit/"; then
    echo "[Transit] Moteur déjà activé."
else
    echo "[Transit] Activation du moteur de chiffrement..."
    vault secrets enable transit
fi

# Création de la clé maîtresse pour l'anonymisation des données utilisateurs
vault write -f transit/keys/transcendence-pii-key 2>/dev/null || true
echo "[Transit] Clé de chiffrement 'transcendence-pii-key' opérationnelle."

# ==============================================================================
# RÉCAPITULATIF DE DÉBOGAGE (DEV MODE UNIQUEMENT)
# ==============================================================================
# Affiche les secrets générés pour permettre au développeur de se connecter
# manuellement aux services (PgAdmin, RabbitMQ Management, etc.)
# ==============================================================================
echo "----------------------------------------------------------------"
echo "🎉 INITIALISATION TERMINÉE AVEC SUCCÈS"
echo "----------------------------------------------------------------"
echo "🔐 RabbitMQ User : ${RABBITMQ_USER}"
echo "🔐 RabbitMQ Pass : ${RABBITMQ_PASS}"
echo "----------------------------------------------------------------"
echo "🔐 Postgres User : ${POSTGRES_USER}"
echo "🔐 Postgres Pass : ${POSTGRES_PASS}"
echo "----------------------------------------------------------------"
echo "⚠️  NOTE IMPORTANTE :"
echo "   Ces mots de passe sont dynamiques et changent à chaque"
echo "   redémarrage complet (docker compose down -v)."
echo "   Ils sont stockés de manière sécurisée dans Vault."
echo "----------------------------------------------------------------"