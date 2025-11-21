# Documentation Technique : Service HashiCorp Vault

## 1\. Vue d'ensemble

Ce document décrit l'architecture de sécurité centralisée via HashiCorp Vault pour le projet `ft_transcendence`.
Vault est utilisé pour répondre aux exigences du module **Cybersecurity** (V.6) et **Security Concerns** (IV.4) du sujet.

**Objectifs :**

  * Stockage sécurisé des secrets (non-commités sur Git).
  * Gestion des certificats SSL/TLS pour le HTTPS (PKI).
  * Chiffrement des données personnelles pour le GDPR (Transit).

-----

## 2\. Structure du Moteur Key-Value (KV v2)

Nous utilisons le moteur de secrets versionné (`kv-v2`) monté sur le chemin `secret/`.

### A. Infrastructure (`secret/infra/...`)

Ces secrets sont consommés par les conteneurs de services tiers au démarrage.

| Chemin Vault | Clés | Description | Consommateur |
| :--- | :--- | :--- | :--- |
| `secret/infra/postgres` | `superuser_name`<br>`superuser_password` | Identifiants "root" pour l'instance PostgreSQL principale. | PostgreSQL |
| `secret/infra/rabbitmq` | `user`<br>`password`<br>`erlang_cookie` | Identifiants admin et cookie de cluster. | RabbitMQ, Microservices |
| `secret/infra/elastic` | `password` | Mot de passe du super-user `elastic`. | Elasticsearch, Logstash, Kibana |
| `secret/infra/kibana` | `encryption_key` | Clé de chiffrement des objets sauvegardés (xpack). | Kibana |
| `secret/infra/grafana` | `admin_password` | Mot de passe administrateur. | Grafana |

### B. Application (`secret/app/...`)

Ces secrets sont récupérés dynamiquement par les microservices Node.js (NestJS/Fastify) au démarrage.

| Chemin Vault | Clés | Description | Consommateur |
| :--- | :--- | :--- | :--- |
| `secret/app/common` | `node_env`<br>`jwt_secret` | Environnement (`development`) et clé secrète pour signer/vérifier les tokens JWT (Auth & Gateway). | Tous |
| `secret/app/auth` | `github_client_id`<br>`github_client_secret` | Identifiants pour l'application OAuth2 GitHub. | Service Auth |
| `secret/app/database` | `host`<br>`port`<br>`db_name` | Informations de connexion partagées PostgreSQL. | Tous les services avec DB |
| `secret/app/ai` | *(Configuration)* | Paramètres de difficulté ou configs du bot (pas de clés API). | Service AI |

-----

## 3\. Infrastructure à Clé Publique (PKI)

Le sujet impose l'utilisation de HTTPS (WSS) pour toutes les connexions. Vault agira comme notre Autorité de Certification (CA) interne.

### Configuration PKI

  * **Rôle Vault :** `transcendence-dot-local`
  * **Domaine racine :** `transcendence.localhost`
  * **TTL Certificats :** 720h (30 jours) pour éviter de régénérer trop souvent en dev.

### Certificats à générer

Un script devra générer ces certificats et les placer dans un volume partagé (`./infrastructure/certs`) accessible par Nginx.

1.  **Certificat Nginx (Frontend/Gateway) :**
      * **Common Name (CN) :** `transcendence.localhost`
      * **SANs (Subject Alternative Names) :** `www.transcendence.localhost`, `api.transcendence.localhost`
      * **Usage :** Permet au navigateur d'accéder au site en HTTPS sans erreur (après ajout du CA racine au navigateur).

-----

## 4\. Moteur Transit (Encryption as a Service)

Ce moteur est utilisé pour le module **GDPR** afin d'anonymiser les données sensibles sans gérer les clés de chiffrement côté applicatif.

  * **Clé de chiffrement :** `transcendence-pii-key` (Type: `aes-256-gcm`)
  * **Fonctionnement :**
    1.  Le service `User` reçoit une donnée sensible (ex: email).
    2.  Il envoie la donnée brute à Vault (`POST /transit/encrypt/transcendence-pii-key`).
    3.  Vault retourne le texte chiffré (`vault:v1:bz3...`).
    4.  Le service `User` stocke ce texte chiffré dans PostgreSQL.
  * **Conformité GDPR (Droit à l'oubli) :**
      * Pour "oublier" totalement les utilisateurs ou invalider les données en cas de fuite DB, il suffit de faire une rotation de clé ou de supprimer la clé dans Vault. Les données en base deviennent illisibles instantanément.

-----

## 5\. Plan d'implémentation (Prochaines étapes)

Pour rendre ce système opérationnel, nous devrons développer les éléments suivants :

### A. Script `init_vault.sh`

Un script shell qui sera exécuté par le conteneur Vault (ou via un conteneur éphémère) au premier lancement. Il devra :

1.  Attendre que Vault soit prêt.
2.  Se connecter avec `VAULT_ROOT_TOKEN`.
3.  Activer les moteurs (`kv`, `pki`, `transit`).
4.  Injecter les secrets par défaut définis ci-dessus.
5.  Générer le certificat racine et le certificat serveur pour Nginx.

### B. Intégration Backend (Package `common`)

Dans le `pnpm workspace`, nous créerons un module partagé (ex: `@transcendence/config`) utilisé par tous les microservices.
Ce module sera responsable de :

  * Se connecter à Vault au démarrage de l'application.
  * Récupérer les secrets nécessaires.
  * Injecter ces secrets dans le `ConfigService` de NestJS/Fastify.
  * Ainsi, le code applicatif utilisera `configService.get('DB_PASSWORD')` sans savoir que cela vient de Vault.

### C. Intégration Infrastructure

Mise à jour du `docker-compose.yml` pour monter les volumes de certificats générés par Vault vers Nginx et RabbitMQ.

```yaml
# Exemple conceptuel pour Nginx plus tard
volumes:
  - ./infrastructure/certs:/etc/nginx/certs:ro
```