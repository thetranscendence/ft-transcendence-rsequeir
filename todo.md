# TODO LIST - ft_transcendence

## 1. Infrastructure & Monitoring
- [Monitoring] **Prometheus & Grafana** :
  - Déployer Prometheus (collecte de métriques) et Grafana (visualisation).
  - Configurer les datasources et importer des dashboards par défaut (Node Exporter, métriques applicatives).
- [Orchestration] **Probes** : Ajouter `livenessProbe` et `readinessProbe` sur tous les services d'infrastructure.

## 2. Développement & Packages Partagés (TypeScript)
*Créer des librairies internes (dans `packages/`) pour standardiser le code des microservices :*

- [Package] **@transcendence/config (Vault)** :
  - Créer un service capable de lire les secrets injectés (fichiers) OU de requêter l'API Vault directement (pour le chiffrement GDPR/Transit).
  - Centraliser la validation des variables d'environnement (zod/joi).
- [Package] **@transcendence/event (RabbitMQ)** :
  - Abstraire la connexion AMQP et la gestion des échanges/files.
  - Fournir des décorateurs ou services typés pour publier/souscrire aux événements définis dans `EVENTS_ARCHITECTURE.md`.
- [Package] **@transcendence/logger (ELK)** :
  - Configurer un logger (basé sur Pino ou Winston) qui formate les logs en JSON.
  - Envoyer les logs vers le service Logstash (via TCP/UDP) en plus de la console standard.
- [Package] **@transcendence/metrics (Prometheus)** :
  - Exposer un endpoint `/metrics` standard pour le scraping Prometheus.
  - Fournir des helpers pour créer des compteurs/gauges métiers (ex: "parties jouées", "utilisateurs connectés").

## 3. Sécurité Kubernetes & Réseau
- [Ingress] **HTTPS/WSS** : Forcer le HTTPS et le support WebSocket Sécurisé (WSS).
- [Réseau] **NetworkPolicies** : Isoler les flux réseau (ex: seul Logstash parle à Elastic, seul le Gateway parle au Frontend).
- [Context] **SecurityContext** : Durcir les pods (`runAsNonRoot`, `readOnlyRootFilesystem`) pour limiter la surface d'attaque.

## 4. Backend & Robustesse
- [Node.js] **Graceful Shutdown** : Gérer `SIGTERM` dans les services Fastify pour couper proprement les connexions (SQLite, RabbitMQ) lors des redémarrages.




- Extraire le Database Service du template pour créer un package qui gère les communications avec la base de données et qui soit réutilisable par les autres microservices.

- Créer un outil pour ajouter / modifier / supprimer un nouveau service applicatif sur la base du service-template : Configuration, Vault, K3s, etc...

- Rédiger un document sur comment utiliser le template pour créer un nouveau service : Création du ServiceAccount, Création du rôle Vault, création de la politique Vault, Création du manifeste K8s, autres ?