FROM node:24-alpine

# Installation de pnpm
ENV PNPM_HOME="/pnpm"
ENV PATH="$PNPM_HOME:$PATH"
RUN corepack enable

WORKDIR /usr/src/app

# ==============================================================================
# 1. COPIE DES FICHIERS DE CONFIGURATION (DEPENDENCIES LAYER)
# ==============================================================================

# Fichiers de configuration du Workspace (Racine)
COPY pnpm-lock.yaml ./
COPY package.json ./
COPY pnpm-workspace.yaml ./

# Manifestes des dépendances spécifiques
# On ne copie QUE le package.json de la librairie dont on a besoin
COPY packages/my-fastify-decorators/package.json ./packages/my-fastify-decorators/
COPY apps/backend-gateway/package.json ./apps/backend-gateway/

# 3. Installation des dépendances (Frozen lockfile pour la reproducibilité)
RUN pnpm install --frozen-lockfile

# ==============================================================================
# 2. COPIE DU CODE SOURCE (APPLICATION LAYER)
# ==============================================================================

# Copie du code source de la librairie locale spécifique
COPY packages/my-fastify-decorators ./packages/my-fastify-decorators

# Copie du code source du Gateway
COPY apps/backend-gateway ./apps/backend-gateway

# ==============================================================================
# 3. BUILD & START
# ==============================================================================

# Build de la librairie locale
# Le gateway a besoin que la lib soit transpilée (création du dossier dist/)
RUN pnpm --filter my-fastify-decorators run build

RUN pnpm --filter backend-gateway run build

# Exposition et Démarrage
EXPOSE 3000

# En mode dev, on utilise ts-node-dev (défini dans le package.json du gateway)
CMD ["node", "apps/backend-gateway/dist/main.js"]