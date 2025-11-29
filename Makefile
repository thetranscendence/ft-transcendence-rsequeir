# --- CONFIGURATION K8S ---
KUBECTL = kubectl
IMAGES  = gateway:latest # Ajoutez ici vos autres images (frontend, auth, etc.)

# ...

up: build import deploy
	@echo "🚀 Cluster K3s prêt !"

# Construction
build:
	docker build -t gateway:latest -f apps/backend-gateway/Dockerfile .
    # Ajoutez les autres builds ici

# Importation dans le registre K3s
import:
	@echo "📦 Transfert des images vers K3s..."
	@for img in $(IMAGES); do \
		echo "   -> Importation de $$img"; \
		docker save $$img | sudo k3s ctr images import -; \
	done

deploy:
	@echo "Déploiement des ressources K8s..."
	# 1. Création du secret global (inchangé)
	$(KUBECTL) create secret generic global-env --from-env-file=$(ENV_FILE) || true
	
	# 2. Installation de Vault via Helm
	# On ajoute le repo Hashicorp si nécessaire
	helm repo add hashicorp https://helm.releases.hashicorp.com || true
	helm repo update
	# Installation en mode Dev avec l'Injecteur activé
	helm upgrade --install vault hashicorp/vault \
		--set "server.dev.enabled=true" \
		--set "server.dev.devRootToken=$(grep VAULT_ROOT_TOKEN .env | cut -d '=' -f2)" \
		--set "injector.enabled=true" \
		--wait

	# 3. Application des autres manifestes (vos apps et configs)
	$(KUBECTL) apply -f infrastructure/k8s/base/
	$(KUBECTL) apply -f infrastructure/k8s/apps/

	@echo "Déploiement terminé."