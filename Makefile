# ==============================================================================
# MAKEFILE - PILOTAGE DE L'INFRASTRUCTURE (ft_transcendence)
# ==============================================================================
# DESCRIPTION :
#   Point d'entrée unique pour gérer le cycle de vie de l'application.
#   Ce fichier encapsule les commandes Docker Compose complexes pour offrir
#   une interface simple et standardisée.
#
# [Ref Subject: IV.2 Minimal technical requirement - Single command line execution]
# ==============================================================================

# --- CONFIGURATION ---

# Chemin relatif vers le fichier d'orchestration
COMPOSE_FILE	= infrastructure/docker-compose.yml

# Fichier de variables d'environnement (Secrets & Config)
# [IV.4] Security concerns : Les secrets ne sont pas commîtés, ils sont lus ici.
ENV_FILE			= .env

# --- MOTEUR DOCKER ---

# Commande de base encapsulée.
# L'option '--env-file' est CRUCIALE ici : elle force Docker à charger le .env
# depuis la racine (là où est le Makefile) et non depuis le dossier infrastructure/,
# ce qui permet de partager les variables entre le Makefile et le Compose.
DOCKER_CMD		= docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

# ==============================================================================
# RÈGLES DU CYCLE DE VIE
# ==============================================================================

# Règle par défaut (Convention Make)
all: up

# Démarrage de la stack en mode détaché (Background)
# --build : Force la reconstruction des images (utile si on modifie le code/Dockerfile).
up:
	@echo "Démarrage de l'infrastructure ft_transcendence..."
	$(DOCKER_CMD) up -d --build

# Arrêt propre des services (Graceful Shutdown)
# NOTE : Cette commande conserve les volumes (Données BDD) et les réseaux.
down:
	@echo "Arrêt des services en cours..."
	$(DOCKER_CMD) down

# Redémarrage complet (Clean + Up)
# Utile pour remettre l'environnement à zéro et appliquer des changements majeurs.
re: clean up

# Configuration de l'environnement de développement (DX)
# ------------------------------------------------------------------------------
# Cette commande prépare votre machine HÔTE pour le codage (VSCode, ESLint...).
# Elle installe Node.js, pnpm et les dépendances via un script dédié.
#
# NOTE :
# Cette étape est OPTIONNELLE. L'évaluation doit se faire via 'make up' (Docker).
# Ce setup sert uniquement à éviter les erreurs dans l'IDE du développeur.
# ------------------------------------------------------------------------------
dev-setup:
	@./scripts/dev_setup.sh

# ==============================================================================
# OUTILS DE DÉBOGAGE & MAINTENANCE
# ==============================================================================

# Affichage des logs en temps réel
# ------------------------------------------------------------------------------
# USAGE :
#   make logs            -> Logs de tous les services mélangés
#   make logs s=nginx    -> Logs du service 'nginx' uniquement
#   make logs s=vault    -> Logs du service 'vault' uniquement
# ------------------------------------------------------------------------------
logs:
	@echo "Affichage des logs $(if $(s),pour le service: $(s),global)..."
	$(DOCKER_CMD) logs -f $(s)

# État des conteneurs (Status, Ports, Healthchecks)
ps:
	@echo "État des services :"
	$(DOCKER_CMD) ps

# Connexion shell interactive dans un conteneur
# ------------------------------------------------------------------------------
# USAGE : make docker-sh s=nginx
# ------------------------------------------------------------------------------
docker-sh:
	@if [ -z "$(s)" ]; then \
		echo "Erreur : Veuillez spécifier un service. Exemple : make docker-sh s=nginx"; \
	else \
		echo "Connexion au shell du service $(s)..."; \
		docker exec -it $(s) /bin/sh; \
	fi

# ==============================================================================
# NETTOYAGE (RESET)
# ==============================================================================

# Nettoyage COMPLET et DESTRUCTIF
# ⚠️  ATTENTION : Cette commande supprime tout !
#   - Arrête les conteneurs
#   - Supprime les réseaux
#   - Supprime les images construites (--rmi all)
#   - Supprime les VOLUMES (-v) -> Perte définitive des données DB et Secrets Vault
#   - Supprime les orphelins (--remove-orphans)
clean:
	@echo "Nettoyage complet (Deep Clean)..."
	@echo "⚠️  ATTENTION : Toutes les données persistantes (DB, Vault) seront effacées."
	$(DOCKER_CMD) down -v --rmi all --remove-orphans

# Protection contre les conflits de noms de fichiers
.PHONY: all up down logs ps clean re