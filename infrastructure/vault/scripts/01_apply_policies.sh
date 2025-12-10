#!/bin/bash
# ==============================================================================
# MODULE 01 : APPLICATION DES POLITIQUES DE SÉCURITÉ (ACL)
# ==============================================================================
# DESCRIPTION :
#   Ce script déploie les politiques (Policies) définies au format HCL dans
#   le dossier '../config/policies/'.
#   Une "Policy" dans Vault définit QUI a le droit de faire QUOI sur QUEL chemin.
#
# ACTIONS :
#   1. Détection automatique des fichiers .hcl de configuration.
#   2. Injection du contenu des politiques dans Vault via l'API.
#   3. Convention de nommage : nom_fichier.hcl -> nom_fichier-policy
# ==============================================================================

# Arrêt immédiat en cas d'erreur
set -e

# ==============================================================================
# 1. CONTRÔLE DE L'ENVIRONNEMENT
# ==============================================================================

# Vérification défensive des fonctions de logging
if ! declare -F log_info > /dev/null; then
    echo "Erreur : Ce script doit être lancé via l'orchestrateur init.sh"
    exit 1
fi

log_info "Démarrage du module de gestion des Politiques (Policies)..."

# Résolution des chemins relatifs
SCRIPTS_DIR=$(dirname "$(realpath "$0")")
POLICIES_DIR="$SCRIPTS_DIR/../config/policies"

# Vérification de l'existence du dossier de configuration
if [ ! -d "$POLICIES_DIR" ]; then
    log_error "Dossier de politiques introuvable : $POLICIES_DIR"
    exit 1
fi

# ==============================================================================
# 2. APPLICATION DES POLITIQUES
# ==============================================================================

# Activation du mode "nullglob" : si aucun fichier .hcl n'existe, la boucle ne s'exécute pas
shopt -s nullglob
files=("$POLICIES_DIR"/*.hcl)

if [ ${#files[@]} -eq 0 ]; then
    log_warn "Aucun fichier .hcl trouvé dans $POLICIES_DIR."
    exit 0
fi

count=0

for policy_file in "${files[@]}"; do
    # Extraction du nom de base sans extension (ex: rabbitmq.hcl -> rabbitmq)
    filename=$(basename "$policy_file" .hcl)
    
    # Convention de nommage : ajout du suffixe "-policy" pour clarté dans l'UI Vault
    policy_name="${filename}-policy"
    
    log_info "Traitement de la politique : $filename"

    # EXPLICATION TECHNIQUE :
    # On utilise 'kubectl exec -i' (interactive) pour passer le contenu du fichier
    # local via l'entrée standard (stdin) vers la commande vault dans le pod.
    # Cela évite de devoir copier les fichiers physiquement dans le pod.
    
    if cat "$policy_file" | kubectl exec -i vault-0 -- sh -c \
        "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault policy write $policy_name -" > /dev/null 2>&1; then
        
        log_success "Politique '$policy_name' appliquée avec succès."
        ((count+=1))
    else
        log_error "Échec lors de l'application de '$policy_name'."
        exit 1
    fi
done

log_info "Total : $count politique(s) mise(s) à jour."