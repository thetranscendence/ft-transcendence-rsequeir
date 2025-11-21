# ==============================================================================
# MAKEFILE - GESTION DE L'INFRASTRUCTURE (ft_transcendence)
# ==============================================================================
# Ce Makefile permet de piloter l'ensemble de l'environnement Docker.
# Il gère l'injection des variables d'environnement et le cycle de vie des conteneurs.
# [Ref Subject: IV.2 Minimal technical requirement - Single command line execution]
# ==============================================================================

# --- CONFIGURATION ---

# Chemin vers le fichier de configuration Docker Compose principal
COMPOSE_FILE	= infrastructure/docker-compose.yml

# Fichier contenant les secrets et variables (ne doit pas être commité)
# [Ref Subject: IV.4 Security concerns]
ENV_FILE			= .env

# --- COMMANDE BASE DOCKER ---

# Construction de la commande Docker Compose.
# L'option '--env-file' est CRUCIALE ici : elle force Docker à lire le fichier .env
# situé à la racine du projet, même si le fichier YAML est dans un sous-dossier.
# Sans cela, les variables ne seraient pas trouvées.
DOCKER_CMD		= docker compose --env-file $(ENV_FILE) -f $(COMPOSE_FILE)

# ==============================================================================
# RÈGLES
# ==============================================================================

# Règle par défaut : lance l'application
all: up

# Démarre les services en arrière-plan (Detached mode)
# --build : Force la reconstruction des images si le Dockerfile a changé
up:
	@echo "Démarrage de l'infrastructure ft_transcendence..."
	$(DOCKER_CMD) up -d --build

# Arrête et supprime les conteneurs et les réseaux créés par 'up'
down:
	@echo "Arrêt des services..."
	$(DOCKER_CMD) down

# Affiche les logs de tous les services en temps réel (-f = follow)
# Utile pour le débogage immédiat sans entrer dans les conteneurs
logs:
	$(DOCKER_CMD) logs -f

# Nettoyage COMPLET de l'environnement (Hard Reset)
# ⚠️ ATTENTION : Cette commande est destructive !
# -v								: Supprime les VOLUMES (bases de données, logs persistants, etc.)
# --rmi all					: Supprime toutes les images associées au service
# --remove-orphans	: Nettoie les conteneurs "orphelins" non définis dans le YAML actuel
clean:
	@echo "Nettoyage complet (conteneurs, volumes, images)..."
	$(DOCKER_CMD) down -v --rmi all --remove-orphans

# Redémarrage complet (Stop + Clean + Start) pour repartir sur une base saine
re: clean up

# Indique que ces règles ne correspondent pas à des fichiers physiques
.PHONY: all up down logs clean re