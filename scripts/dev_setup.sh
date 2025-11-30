#!/bin/bash
# ==============================================================================
# SCRIPT DE CONFIGURATION : ENVIRONNEMENT DE DÉVELOPPEMENT LOCAL
# ==============================================================================
# DESCRIPTION :
#   Ce script prépare la machine HÔTE (votre ordinateur) pour le développement.
#   Il installe Node.js et pnpm via NVM pour garantir que votre IDE (VSCode)
#   puisse analyser le code, fournir l'autocomplétion et le linting.
#
# ⚠️ IMPORTANT :
#   Ce script n'est PAS nécessaire pour lancer le projet via Docker (`make up`).
#   Docker est autonome. Ce script sert uniquement au confort du développeur
#   pour éviter les erreurs "Module not found" dans l'éditeur de code.
# ==============================================================================

# Arrêt du script en cas d'erreur (robustesse)
set -e

echo "Configuration de l'environnement local..."

# Passage en root pour installer les packages et configurer l'utilisateur principal
# Passage en root avec un bloc 'Heredoc' pour éviter les problèmes de guillemets
su root -c "apt update -y && apt install sudo vim git curl build-essential ca-certificates gnupg -y && install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && chmod a+r /etc/apt/keyrings/docker.asc && echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null && apt update -y && apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin -y && systemctl start docker && systemctl enable docker && echo \"transcendence ALL=(ALL:ALL) NOPASSWD: ALL\" > /etc/sudoers.d/transcendence && sudo usermod -aG docker transcendence"

# Installation de k3s
curl -sfL https://get.k3s.io | sh -

# Configuration de l'acces utilisateur Kubeconfig
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config
sudo kubectl get nodes

# Installation de Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# ==============================================================================
# 1. GESTIONNAIRE DE VERSION NODE (NVM)
# ==============================================================================
# Dans les environnements restreints (comme les clusters 42), nous n'avons pas
# les droits root pour mettre à jour le Node.js système. NVM est la solution standard.
export NVM_DIR="$HOME/.nvm"

if [ -s "$NVM_DIR/nvm.sh" ]; then
    # Chargement de NVM dans le shell courant
    . "$NVM_DIR/nvm.sh"
else
    echo "NVM n'est pas détecté. Lancement de l'installation..."
    
    # Installation via le script officiel
    # Note : On utilise curl | bash comme recommandé par la doc officielle NVM
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    
    # Chargement immédiat de NVM pour la suite de ce script
    . "$NVM_DIR/nvm.sh"
    
    echo "NVM installé avec succès."
fi

# ==============================================================================
# 2. INSTALLATION DE NODE.JS
# ==============================================================================
# Nous utilisons la version LTS (Long Term Support) pour garantir la stabilité.
# Cela doit correspondre à la version définie dans 'package.json' > engines.
echo "Installation/Activation de Node.js (LTS)..."
nvm install --lts
nvm use --lts

# ==============================================================================
# 3. INSTALLATION DE PNPM
# ==============================================================================
# pnpm est choisi pour sa gestion efficace de l'espace disque et sa rapidité
# dans les monorepos (Workspaces).
echo "Vérification de pnpm..."
if ! command -v pnpm &> /dev/null; then
    echo "   Installation de pnpm via npm..."
    npm install -g pnpm
else
    echo "  pnpm est déjà installé."
fi

# ==============================================================================
# 4. INSTALLATION DES DÉPENDANCES (MONOREPO)
# ==============================================================================
# Installe toutes les librairies définies dans le 'package.json' racine
# ET dans les sous-dossiers 'apps/*' et 'packages/*'.
echo "Installation des dépendances du projet..."
pnpm install

echo "----------------------------------------------------------------"
echo "ENVIRONNEMENT DE DÉVELOPPEMENT PRÊT !"
echo "   Vous pouvez maintenant ouvrir VSCode sans erreurs d'import."
echo "----------------------------------------------------------------"