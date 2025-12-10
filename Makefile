# ==============================================================================
# MAKEFILE - PILOTAGE INFRASTRUCTURE (KUBERNETES / K3S)
# ==============================================================================
# PRÉ-REQUIS :
#   - Docker & K3s installés
#   - kubectl & helm configurés
#   - Utilitaire 'scripts/logger.sh' présent
# ==============================================================================

# Force l'utilisation de Bash
SHELL := /bin/bash

# --- CONFIGURATION ---
KUBECTL     = kubectl
ENV_FILE    = .env
K8S_DIR     = ./infrastructure/k8s
VAULT_DIR   = ./infrastructure/vault
LOGGER      = ./scripts/logger.sh

IMAGES      = gateway:latest
VAULT_TOKEN = $(shell grep VAULT_ROOT_TOKEN $(ENV_FILE) | cut -d '=' -f2)

# --- MACROS DE LOGGING ---
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
up: build import deploy-infra config-vault deploy-services deploy-apps restart-pods
	@$(LOG_SUCCESS) "Environnement ft_transcendence opérationnel !"

# 1. Build
build:
	@$(LOG_STEP) "Phase 1 : Construction des artefacts Docker"
	@$(LOG_INFO) "Build de l'image : gateway:latest"
	@docker build -t gateway:latest -f apps/backend-gateway/Dockerfile . > /dev/null

# 2. Import
import:
	@$(LOG_STEP) "Phase 2 : Importation dans le registre Cluster (K3s)"
	@for img in $(IMAGES); do \
		source $(LOGGER) && log_info "Transfert de l'image $$img vers k3s..."; \
		docker save $$img | sudo k3s ctr images import - > /dev/null; \
	done

# 3. Infra (Vault + Base)
deploy-infra:
	@$(LOG_STEP) "Phase 3 : Déploiement de l'Infrastructure"
	@$(LOG_INFO) "Application des manifestes de base..."
	@$(KUBECTL) create secret generic global-env --from-env-file=$(ENV_FILE) --dry-run=client -o yaml | $(KUBECTL) apply -f - > /dev/null
	@$(KUBECTL) apply -f $(K8S_DIR)/base/ > /dev/null

	@# On vérifie si Vault tourne déjà pour ne SURTOUT PAS le redémarrer (perte de RAM)
	@if helm status vault > /dev/null 2>&1; then \
		source $(LOGGER) && log_info "Vault est déjà installé. (Conservation des secrets en mémoire)"; \
	else \
		source $(LOGGER) && log_warn "Installation de Vault (Helm Chart)..."; \
		helm repo add hashicorp https://helm.releases.hashicorp.com > /dev/null 2>&1; \
		helm repo update > /dev/null 2>&1; \
		helm upgrade --install vault hashicorp/vault \
			--set "server.dev.enabled=true" \
			--set "server.dev.devRootToken=$(VAULT_TOKEN)" \
			--set "injector.enabled=true" \
			--wait > /dev/null; \
		source $(LOGGER) && log_success "Vault installé."; \
	fi

# 4. Config Vault
config-vault:
	@# Le script init.sh est idempotent : il ne réécrit pas les secrets existants
	@bash $(VAULT_DIR)/init.sh

# 5. Services Tiers
deploy-services:
	@$(LOG_STEP) "Phase 5 : Déploiement des Services Tiers"
	@$(LOG_INFO) "Configuration Logstash..."
	@$(KUBECTL) create configmap logstash-config \
		--from-file=logstash.conf=./infrastructure/logstash/pipeline/logstash.conf \
		--dry-run=client -o yaml | $(KUBECTL) apply -f - > /dev/null
	@$(LOG_INFO) "Application des dépendances (Data & Messaging)..."
	@$(KUBECTL) apply -f $(K8S_DIR)/dependencies/ > /dev/null
	@$(LOG_INFO) "Initialisation des utilisateurs Elasticsearch..."
	@$(KUBECTL) delete job init-es-users --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) apply -f $(K8S_DIR)/dependencies/init-es-users.yaml > /dev/null

# 6. Apps
deploy-apps:
	@$(LOG_STEP) "Phase 6 : Déploiement des Applications"
	@$(KUBECTL) apply -f $(K8S_DIR)/apps/ > /dev/null

# 7. Refresh
restart-pods:
	@$(LOG_INFO) "Rolling Update des pods pour prise en compte..."
	@$(KUBECTL) rollout restart deployment gateway > /dev/null

# ==============================================================================
# ARRÊT (PERSISTANT)
# ==============================================================================
# Cette commande arrête les services mais GARDE Vault et les PVC.
# Au prochain 'make up', tout repartira avec les MÊMES mots de passe.
down:
	@$(LOG_HEADER) "ARRÊT DES SERVICES (SAFE MODE)"
	@$(LOG_INFO) "Suppression des applications et dépendances..."
	@$(KUBECTL) delete -f $(K8S_DIR)/apps/ --ignore-not-found > /dev/null
	@$(KUBECTL) delete -f $(K8S_DIR)/dependencies/ --ignore-not-found > /dev/null
	@$(KUBECTL) delete secret global-env --ignore-not-found > /dev/null
	@$(KUBECTL) delete configmap logstash-config --ignore-not-found > /dev/null
	
	@# INFO CRITIQUE POUR L'UTILISATEUR
	@source $(LOGGER) && echo ""
	@source $(LOGGER) && echo -e "\033[33m[IMPORTANT] Vault a été laissé actif pour conserver les secrets en mémoire.\033[0m"
	@source $(LOGGER) && echo -e "\033[33m            Les volumes persistants (PVC) ont également été conservés.\033[0m"
	@source $(LOGGER) && echo -e "\033[33m            Utilisez 'make fclean' pour tout détruire.\033[0m"
	@source $(LOGGER) && echo ""
	@$(LOG_SUCCESS) "Environnement arrêté (Données préservées)."

# ==============================================================================
# NETTOYAGE (DESTRUCTIF)
# ==============================================================================
# Cette commande efface TOUT : Secrets Vault et Données DB.
fclean:
	@$(LOG_HEADER) "NETTOYAGE COMPLET (FACTORY RESET)"
	@$(LOG_WARN) "Arrêt de tous les services..."
	@$(MAKE) -s down
	
	@$(LOG_WARN) "Désinstallation de Vault (Perte des secrets)..."
	@helm uninstall vault > /dev/null 2>&1 || true
	
	@$(LOG_WARN) "Suppression définitive des volumes de données (PVC)..."
	@$(KUBECTL) delete pods --all --force --grace-period=0 --ignore-not-found > /dev/null 2>&1
	@$(KUBECTL) delete pvc --all --ignore-not-found > /dev/null
	@$(KUBECTL) delete jobs --all --ignore-not-found > /dev/null
	
	@$(LOG_SUCCESS) "Cluster nettoyé. Toutes les données sont effacées."

re: fclean up