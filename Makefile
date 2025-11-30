# ==============================================================================
# MAKEFILE - PILOTAGE INFRASTRUCTURE (KUBERNETES / K3S)
# ==============================================================================

# --- CONFIGURATION ---
KUBECTL     = kubectl
ENV_FILE    = .env
K8S_DIR     = ./infrastructure/k8s
SCRIPTS_DIR = ./infrastructure/k8s/scripts

# Liste des images à construire (Ajouter ici frontend, auth, etc.)
IMAGES      = gateway:latest

# Extraction du token pour Helm
VAULT_TOKEN = $(shell grep VAULT_ROOT_TOKEN $(ENV_FILE) | cut -d '=' -f2)

export VAULT_ROOT_TOKEN=${VAULT_TOKEN}
# ==============================================================================
# RÈGLES DU CYCLE DE VIE
# ==============================================================================

all: up

# Orchestration complète : Build -> Import K3s -> Deploy Infra -> Config -> Deploy Apps
up: build import deploy-infra config-vault deploy-services deploy-apps restart-pods
	@echo "Environnement ft_transcendence prêt sur Kubernetes !"

# 1. Construction des images Docker
build:
	@echo "Construction des images..."
	docker build -t gateway:latest -f apps/backend-gateway/Dockerfile .

# 2. Importation dans le registre K3s (Requis pour que K3s voie les images)
import:
	@echo "Importation des images dans K3s..."
	@for img in $(IMAGES); do \
		echo "   -> Transfert de $$img"; \
		docker save $$img | sudo k3s ctr images import -; \
	done

# 3. Déploiement de l'Infrastructure (Vault via Helm + Base)
deploy-infra:
	@echo "Déploiement de l'infrastructure..."
	# Création du secret global (s'il n'existe pas)
	$(KUBECTL) create secret generic global-env --from-env-file=$(ENV_FILE) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	
	# Installation de Vault via Helm
	@echo "   -> Installation de Vault (Chart Helm)..."
	helm repo add hashicorp https://helm.releases.hashicorp.com > /dev/null 2>&1 || true
	helm repo update > /dev/null 2>&1
	helm upgrade --install vault hashicorp/vault \
		--set "server.dev.enabled=true" \
		--set "server.dev.devRootToken=$(VAULT_TOKEN)" \
		--set "injector.enabled=true" \
		--wait
	
	# Application des configs de base (Namespaces, ConfigMaps)
	$(KUBECTL) apply -f $(K8S_DIR)/base/

# 4. Configuration de Vault (Script post-installation)
config-vault:
	@echo "Configuration de Vault..."
	bash $(SCRIPTS_DIR)/config_k8s_vault.sh

# 5. Déploiement des Services Tiers (RabbitMQ, ELK)
deploy-services:
	@echo "Déploiement des services tiers (RabbitMQ, ELK)..."
	
	# A. Création de la ConfigMap Logstash depuis le fichier local
	# Cela permet d'éditer logstash.conf dans votre IDE et de le pousser sans reconstruire d'image
	$(KUBECTL) create configmap logstash-config \
		--from-file=logstash.conf=./infrastructure/logstash/pipeline/logstash.conf \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -

	# B. Application des manifestes (RabbitMQ, Elastic, Kibana, Logstash)
	# Note : Vault étant configuré, l'injection de secrets fonctionnera immédiatement
	$(KUBECTL) apply -f $(K8S_DIR)/dependencies/

# 6. Déploiement des Applications (Gateway, Frontend...)
deploy-apps:
	@echo "Déploiement des applications..."
	$(KUBECTL) apply -f $(K8S_DIR)/apps/

# 7. Redémarrage (Sécurité)
restart-pods:
	@echo "Redémarrage pour prise en compte..."
	$(KUBECTL) rollout restart deployment gateway || true

# Nettoyage
down:
	@echo "🛑 Suppression des ressources..."
	$(KUBECTL) delete -f $(K8S_DIR)/apps/ --ignore-not-found
	$(KUBECTL) delete -f $(K8S_DIR)/dependencies/ --ignore-not-found
	helm uninstall vault || true
	$(KUBECTL) delete secret global-env --ignore-not-found
	$(KUBECTL) delete configmap logstash-config --ignore-not-found

re: down up

.PHONY: all up build import deploy-infra config-vault deploy-services deploy-apps restart-pods down re