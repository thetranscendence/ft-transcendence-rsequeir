# ==============================================================================
# MAKEFILE - GESTION DE L'INFRASTRUCTURE (ft_transcendence)
# ==============================================================================
# Ce Makefile est le point d'entrée unique pour piloter l'environnement Docker.
# Il garantit une exécution standardisée et respecte les contraintes du sujet.
#
# [Ref Subject: IV.2 Minimal technical requirement - Single command line execution]
# ==============================================================================

# --- CONFIGURATION ---

# Chemin vers le fichier de configuration Docker Compose principal
COMPOSE_FILE	= infrastructure/docker-compose.yml

# Fichier contenant les secrets (ne doit PAS être commité).
# Utilisé pour injecter le VAULT_ROOT_TOKEN et les configurations initiales.
# [Ref Subject: IV.4 Security concerns]
ENV_FILE			= .env

# --- MOTEUR DOCKER ---

# Construction de la commande de base.
# L'option '--env-file' est CRUCIALE : elle force Docker à charger les variables
# depuis la racine du projet, rendant le .env accessible au docker-compose.yml
# situé dans le sous-dossier 'infrastructure/'.
DOCKER_CMD		= docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

# ==============================================================================
# RÈGLES PRINCIPALES
# ==============================================================================

# Règle par défaut : Démarre l'ensemble de la stack
all: up

# Démarrage des services en mode détaché (arrière-plan)
# --build : Force la recompilation des images si les Dockerfiles ont changé.
up:
	@echo "Démarrage de l'infrastructure ft_transcendence..."
	$(DOCKER_CMD) up -d --build

# Arrêt propre des services (conserve les volumes et les réseaux)
down:
	@echo "Arrêt des services en cours..."
	$(DOCKER_CMD) down

# ==============================================================================
# OUTILS DE DÉBOGAGE & LOGS
# ==============================================================================

# Affiche les logs en temps réel (-f = follow).
# ------------------------------------------------------------------------------
# USAGE :
#   1. Tous les services : make logs
#   2. Un seul service   : make logs s=vault
#                          make logs s=rabbitmq
# ------------------------------------------------------------------------------
logs:
	@echo "Affichage des logs $(if $(s),pour le service: $(s),global)..."
	$(DOCKER_CMD) logs -f $(s)

# Affiche l'état des conteneurs (UP/DOWN, Ports, Healthcheck)
ps:
	@echo "État des services :"
	$(DOCKER_CMD) ps

# ==============================================================================
# NETTOYAGE & MAINTENANCE
# ==============================================================================

# Nettoyage COMPLET de l'environnement (Hard Reset).
# ⚠️  ATTENTION : DESTRUCTIF !
# - Supprime les conteneurs arrêtés.
# -v                : Supprime les VOLUMES (Base de données, Secrets Vault, etc.)
# --rmi all         : Supprime toutes les images associées.
# --remove-orphans  : Nettoie les conteneurs "fantômes" non définis dans le YAML.
clean:
	@echo "🧹 Nettoyage complet (conteneurs, volumes, images, réseaux)..."
	@echo "⚠️  Toutes les données persistantes (DB, Vault) seront perdues."
	$(DOCKER_CMD) down -v --rmi all --remove-orphans

# Redémarrage complet pour repartir sur une base saine (Fresh Start)
re: clean up

# Indique que ces règles ne correspondent pas à des fichiers physiques
.PHONY: all up down logs ps clean re