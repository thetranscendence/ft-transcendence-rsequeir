#!/bin/bash
# ==============================================================================
# UTILITAIRE DE LOGGING PARTAGÉ
# ==============================================================================
# Ce script fournit des fonctions de logging standardisées pour tous les scripts
# du projet (Dev, CI/CD, Infra).
#
# Usage :
#   source ./scripts/logger.sh
#   log_info "Message"
# ==============================================================================

# Couleurs ANSI
RESET='\033[0m'
BOLD='\033[1m'
RED='\033[31m'
GREEN='\033[32m'
YX='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'

log_header() {
    echo -e "${BLUE}${BOLD}========================================================================${RESET}"
    echo -e "${BLUE}${BOLD}[$(date +'%H:%M:%S')] $1${RESET}"
    echo -e "${BLUE}${BOLD}========================================================================${RESET}"
}

log_info() {
    echo -e "${CYAN}[$(date +'%H:%M:%S')] [INFO] ${RESET} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] [OK]   ${RESET} $1"
}

log_warn() {
    echo -e "${YX}[$(date +'%H:%M:%S')] [WARN] ${RESET} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] [ERR]  ${RESET} $1" >&2
}

log_step() {
    echo ""
    echo -e "${BOLD}[$(date +'%H:%M:%S')] [STEP]  $1${RESET}"
    echo -e "${BOLD}------------------------------------------------------------------------${RESET}"
}