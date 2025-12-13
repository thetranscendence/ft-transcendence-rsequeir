# ==============================================================================
# MAKEFILE - ORCHESTRATION INFRASTRUCTURE (KUBERNETES / K3S)
# ==============================================================================
# DESCRIPTION :
#   Point d'entrée unique pour le pilotage du cluster local.
#   Gère le cycle de vie complet : Build -> Déploiement -> Maintenance -> Nettoyage.
#
# PRÉ-REQUIS :
#   - Docker & K3s installés
#   - kubectl & helm configurés
#   - Utilitaire 'scripts/logger.sh' présent pour le formatage des logs
# ==============================================================================

# Force l'utilisation de Bash pour la compatibilité des scripts
SHELL := /bin/bash

# ==============================================================================
# CONFIGURATION ET VARIABLES
# ==============================================================================

KUBECTL     = kubectl
ENV_FILE    = .env
K8S_DIR     = ./infrastructure/k8s
VAULT_DIR   = ./infrastructure/vault
LOGGER      = ./scripts/logger.sh

# Liste des images locales à construire et à injecter dans le registre du cluster
IMAGES      = gateway:latest service-template:latest

# Récupération dynamique du Token Root Vault pour l'installation Helm.
# Ce token permet d'initialiser Vault en mode "Dev" sans avoir à le déverrouiller manuellement.
VAULT_TOKEN = $(shell grep VAULT_ROOT_TOKEN $(ENV_FILE) | cut -d '=' -f2)

# --- MACROS DE LOGGING (Esthétique) ---
LOG_HEADER  = source $(LOGGER) && log_header
LOG_INFO    = source $(LOGGER) && log_info
LOG_SUCCESS = source $(LOGGER) && log_success
LOG_WARN    = source $(LOGGER) && log_warn
LOG_ERROR   = source $(LOGGER) && log_error
LOG_STEP    = source $(LOGGER) && log_step

# ==============================================================================
# RÈGLES DU CYCLE DE VIE
# ==============================================================================

.PHONY: all up build import deploy-infra config-vault deploy-services deploy-apps restart-pods down fclean re

all: up

# ------------------------------------------------------------------------------
# DÉMARRAGE / MISE À JOUR (IDEMPOTENT)
# ------------------------------------------------------------------------------
# Cette règle joue tout le pipeline. Elle est idempotente : peut être lancée
# plusieurs fois sans casser l'existant (sauf redémarrage des pods applicatifs).
up: build import deploy-infra config-vault deploy-services deploy-apps restart-pods
	@$(LOG_SUCCESS) "Environnement ft_transcendence opérationnel !"

# 1. BUILD DES IMAGES
# ------------------------------------------------------------------------------
build:
	@$(LOG_STEP) "Phase 1 : Construction des artefacts Docker"

	@$(LOG_INFO) "Construction de l'image : gateway:latest"
	@docker build -t gateway:latest -f apps/backend-gateway/Dockerfile . > /dev/null

	@$(LOG_INFO) "Construction de l'image : service-template:latest"
	@docker build -t service-template:latest -f apps/service-template/Dockerfile . > /dev/null

# 2. IMPORT DANS LE CLUSTER
# ------------------------------------------------------------------------------
# K3s utilise son propre registre containerd. On doit y transférer nos images locales
# pour que les Pods puissent les utiliser avec 'imagePullPolicy: Never'.
import:
	@$(LOG_STEP) "Phase 2 : Importation dans le registre Cluster (K3s)"
	@for img in $(IMAGES); do \
		source $(LOGGER) && log_info "Transfert de l'image $$img vers k3s..."; \
		docker save $$img | sudo k3s ctr images import - > /dev/null; \
	done

# 3. INFRASTRUCTURE DE SÉCURITÉ (VAULT)
# ------------------------------------------------------------------------------
deploy-infra:
	@$(LOG_STEP) "Phase 3 : Déploiement de l'Infrastructure"
	@$(LOG_INFO) "Application des manifestes de base (Namespaces, ConfigMaps...)..."
	# Création du secret global (env vars) avant tout le reste
	@$(KUBECTL) create secret generic global-env --from-env-file=$(ENV_FILE) --dry-run=client -o yaml | $(KUBECTL) apply -f - > /dev/null
	@$(KUBECTL) apply -f $(K8S_DIR)/base/ > /dev/null

	@# SÉCURITÉ CRITIQUE : Vérification de l'état de Vault.
	@# En mode 'dev', Vault stocke tout en RAM. Si on le redémarre (helm upgrade),
	@# tous les secrets sont PERDUS et les applications crasheront.
	@if helm status vault > /dev/null 2>&1; then \
		source $(LOGGER) && log_info "Vault est déjà installé. (Conservation critique des secrets en mémoire)"; \
	else \
		source $(LOGGER) && log_warn "Installation initiale de Vault (Helm Chart)..."; \
		helm repo add hashicorp https://helm.releases.hashicorp.com > /dev/null 2>&1; \
		helm repo update > /dev/null 2>&1; \
		helm upgrade --install vault hashicorp/vault \
    --set "server.dev.enabled=false" \
    --set "server.dataStorage.enabled=true" \
    --set "server.dataStorage.size=1Gi" \
    --set "server.dataStorage.storageClass=local-path" \
    --set "server.standalone.enabled=true" \
    --set "injector.enabled=true" \
    --wait > /dev/null; \
		source $(LOGGER) && log_success "Vault installé avec succès."; \
	fi

# 4. CONFIGURATION VAULT
# ------------------------------------------------------------------------------
config-vault:
	@# Lance l'orchestrateur de sécurité. Ce script est idempotent.
	@bash $(VAULT_DIR)/init.sh

# 5. SERVICES TIERS (DATA & MESSAGING)
# ------------------------------------------------------------------------------
deploy-services:
	@$(LOG_STEP) "Phase 5 : Déploiement des Services Tiers"
	
	@$(LOG_INFO) "Packaging des scripts d'initialisation (Elasticsearch)..."
	@# Création d'une ConfigMap contenant les scripts shell.
	@# Cela permet de monter les scripts (init + logger) directement dans les conteneurs
	@# sans avoir à créer une image Docker spécifique pour l'initialisation.
	@$(KUBECTL) create configmap es-init-scripts \
		--from-file=init_users.sh=./infrastructure/elasticsearch/scripts/init_es_users.sh \
		--from-file=logger.sh=./scripts/logger.sh \
		--dry-run=client -o yaml | \
		$(KUBECTL) apply -f - > /dev/null

	@$(LOG_INFO) "Configuration du pipeline Logstash..."
	@$(KUBECTL) create configmap logstash-config \
		--from-file=logstash.conf=./infrastructure/logstash/pipeline/logstash.conf \
		--dry-run=client -o yaml | \
		$(KUBECTL) apply -f - > /dev/null

	@$(LOG_INFO) "Déploiement des StatefulSets (Elastic, RabbitMQ, etc.)..."
	@$(KUBECTL) apply -f $(K8S_DIR)/dependencies/ > /dev/null
	
	@$(LOG_INFO) "Exécution du Job d'initialisation Elasticsearch..."
	@# Un Job Kubernetes "Completed" ne peut pas être relancé. On le supprime d'abord
	@# pour forcer sa réexécution (et donc la prise en compte d'éventuels changements de secrets).
	@$(KUBECTL) delete job init-es-users --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) apply -f $(K8S_DIR)/dependencies/init-es-users.yaml > /dev/null

# 6. APPLICATIONS MÉTIERS
# ------------------------------------------------------------------------------
deploy-apps:
	@$(LOG_STEP) "Phase 6 : Déploiement des Applications (Microservices)"
	@$(KUBECTL) apply -f $(K8S_DIR)/apps/ > /dev/null

# 7. REDÉMARRAGE (ROLLING UPDATE)
# ------------------------------------------------------------------------------
restart-pods:
	@$(LOG_INFO) "Rolling Update des pods pour prise en compte des configurations..."
	@$(KUBECTL) rollout restart deployment gateway > /dev/null

# ==============================================================================
# ARRÊT PROPRE (PERSISTANT)
# ==============================================================================
# Arrête les applicatifs mais conserve l'état critique (Secrets Vault & PVC).
# Utile pour éteindre la machine sans perdre la configuration de dev.
down:
	@$(LOG_HEADER) "ARRÊT DES SERVICES (SAFE MODE)"
	@$(LOG_INFO) "Suppression des applications et dépendances..."
	@$(KUBECTL) delete -f $(K8S_DIR)/apps/ --ignore-not-found > /dev/null
	@$(KUBECTL) delete -f $(K8S_DIR)/dependencies/ --ignore-not-found > /dev/null
	
	@$(LOG_INFO) "Nettoyage des configurations volatiles..."
	@$(KUBECTL) delete secret global-env --ignore-not-found > /dev/null
	@$(KUBECTL) delete configmap logstash-config --ignore-not-found > /dev/null
	@$(KUBECTL) delete configmap es-init-scripts --ignore-not-found > /dev/null
	
	@# MESSAGE IMPORTANT POUR L'UTILISATEUR
	@source $(LOGGER) && echo ""
	@source $(LOGGER) && echo -e "\033[33m[IMPORTANT] Vault a été laissé actif pour conserver les secrets en mémoire.\033[0m"
	@source $(LOGGER) && echo -e "\033[33m            Les volumes de données (PVC) ont également été conservés.\033[0m"
	@source $(LOGGER) && echo -e "\033[33m            Pour tout effacer, utilisez : make fclean\033[0m"
	@source $(LOGGER) && echo ""
	@$(LOG_SUCCESS) "Environnement arrêté (Données préservées)."

# ==============================================================================
# NETTOYAGE COMPLET (DESTRUCTIF)
# ==============================================================================
# Réinitialisation totale de l'environnement (Factory Reset).
# Supprime Vault (donc les secrets) et tous les volumes persistants.
fclean:
	@$(LOG_HEADER) "NETTOYAGE COMPLET (FACTORY RESET)"
	
	@$(LOG_WARN) "1. Arrêt des services..."
	@$(MAKE) -s down
	
	@$(LOG_WARN) "2. Désinstallation de Vault (PERTE IRRÉVERSIBLE DES SECRETS)..."
	@helm uninstall vault > /dev/null 2>&1 || true
	
	@$(LOG_WARN) "3. Suppression définitive des volumes de données (PVC)..."
	@$(KUBECTL) delete pods --all --force --grace-period=0 --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) delete pvc --all --ignore-not-found > /dev/null
	@$(KUBECTL) delete jobs --all --ignore-not-found > /dev/null
	
	@$(LOG_SUCCESS) "Cluster nettoyé. Toutes les données sont effacées."

re: fclean up