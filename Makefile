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
	
# 1. Création du secret global
	kubectl create secret generic global-env --from-env-file=$(ENV_FILE) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	
# On supprime le StatefulSet ou le Pod pour forcer un redémarrage à froid
# Cela garantit que Vault oublie son ancien token aléatoire
	helm uninstall vault || true
	$(KUBECTL) delete pod vault-0 --ignore-not-found --wait=true
	
# 3. Installation de Vault via Helm
	@echo "   -> Installation de Vault (Chart Helm)..."
	helm repo add hashicorp https://helm.releases.hashicorp.com > /dev/null 2>&1 || true
	helm repo update > /dev/null 2>&1
	helm upgrade --install vault hashicorp/vault \
		--set "server.dev.enabled=true" \
		--set "server.dev.devRootToken=$(VAULT_TOKEN)" \
		--set "injector.enabled=true" \
		--wait
	
	# 4. Application des configs de base
	$(KUBECTL) apply -f $(K8S_DIR)/base/

# 4. Configuration de Vault (Script post-installation)
config-vault:
	@echo "Configuration de Vault..."
	bash $(SCRIPTS_DIR)/config_k8s_vault.sh

# 5. Déploiement des Services Tiers (RabbitMQ, ELK)
deploy-services:
	@echo "Déploiement des services tiers (RabbitMQ, ELK)..."
	
# Création de la ConfigMap Logstash depuis le fichier local
	$(KUBECTL) create configmap logstash-config \
		--from-file=logstash.conf=./infrastructure/logstash/pipeline/logstash.conf \
		--dry-run=client -o yaml | $(KUBECTL) apply -f -

# Application des manifestes (RabbitMQ, Elastic, Kibana, Logstash)
	$(KUBECTL) apply -f $(K8S_DIR)/dependencies/

# Lancement du Job d'initialisation des utilisateurs ES
# On supprime l'ancien job s'il existe pour forcer sa ré-exécution
	$(KUBECTL) delete job init-es-users --ignore-not-found
	$(KUBECTL) apply -f $(K8S_DIR)/dependencies/init-es-users.yaml

# 6. Déploiement des Applications (Gateway, Frontend...)
deploy-apps:
	@echo "Déploiement des applications..."
	$(KUBECTL) apply -f $(K8S_DIR)/apps/

# 7. Redémarrage (Sécurité)
restart-pods:
	@echo "Redémarrage pour prise en compte..."
	$(KUBECTL) rollout restart deployment gateway

# Nettoyage
down:
	@echo "Suppression des ressources..."
	$(KUBECTL) delete -f $(K8S_DIR)/apps/ --ignore-not-found
	$(KUBECTL) delete -f $(K8S_DIR)/dependencies/ --ignore-not-found
	helm uninstall vault || true
	$(KUBECTL) delete secret global-env --ignore-not-found
	$(KUBECTL) delete configmap logstash-config --ignore-not-found

fclean: down
	@echo "Nettoyage forcé de TOUTES les ressources..."
	# Force la suppression immédiate des pods (grace-period=0)
	$(KUBECTL) delete pods --all --force --grace-period=0 --ignore-not-found
	# Supprime les PVC (Volumes persistants) qui pourraient garder des données corrompues
	$(KUBECTL) delete pvc --all --ignore-not-found
	# Supprime les secrets et configmaps résiduels
	$(KUBECTL) delete secret global-env --ignore-not-found
	$(KUBECTL) delete configmap logstash-config --ignore-not-found
	# Nettoie les jobs terminés ou en erreur
	$(KUBECTL) delete jobs --all --ignore-not-found
	@echo "Cluster nettoyé."

re: fclean up

.PHONY: all up build import deploy-infra config-vault deploy-services deploy-apps restart-pods down fclean re