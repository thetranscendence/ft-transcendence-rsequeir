#!/bin/bash
# ==============================================================================
# MODULE 03 : INFRASTRUCTURE À CLÉ PUBLIQUE (PKI)
# ==============================================================================
# DESCRIPTION :
#   Ce script configure le moteur PKI (Public Key Infrastructure) de Vault.
#   Le sujet impose l'utilisation de HTTPS (WSS) pour toutes les connexions.
#   Plutôt que de gérer des certificats manuellement (openssl), nous utilisons
#   Vault pour générer et signer des certificats à la volée.
#
# ACTIONS :
#   1. Activer le moteur de secrets 'pki'.
#   2. Générer un Certificat Racine (Root CA) auto-signé interne.
#   3. Distribuer ce CA dans un Secret Kubernetes pour la chaîne de confiance.
#   4. Créer un Rôle permettant d'émettre des certificats serveur.
# ==============================================================================

# Arrêt immédiat en cas d'erreur
set -e

# ==============================================================================
# 1. CONTRÔLE DE L'ENVIRONNEMENT
# ==============================================================================

if ! declare -F log_info > /dev/null; then
    echo "❌ Erreur : Ce script doit être lancé via l'orchestrateur init.sh"
    exit 1
fi

log_info "Démarrage du module PKI (Gestion des certificats TLS)..."

# ==============================================================================
# 2. ACTIVATION DU MOTEUR PKI
# ==============================================================================

# On vérifie si le moteur est déjà monté sur le chemin 'pki/'
if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault secrets list" | grep -q "pki/"; then
    log_info "Moteur de secrets 'pki' déjà activé. (Skip)"
else
    log_warn "Activation du moteur PKI..."
    
    # Activation du moteur
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault secrets enable pki"
    
    # Tuning : On augmente le TTL max à 1 an (8760h) pour pouvoir héberger un Root CA
    # Par défaut, Vault a des TTLs beaucoup plus courts.
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault secrets tune -max-lease-ttl=8760h pki"
    
    log_success "Moteur PKI activé et configuré."
fi

# ==============================================================================
# 3. GÉNÉRATION DE L'AUTORITÉ DE CERTIFICATION (ROOT CA)
# ==============================================================================

# On vérifie si un certificat CA existe déjà
if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault read pki/cert/ca" > /dev/null 2>&1; then
    log_info "Certificat Racine (Root CA) déjà existant. (Skip)"
else
    log_warn "Génération du Certificat Racine (Root CA)..."
    
    # 1. Génération interne dans Vault
    # Le certificat est retourné dans le champ 'certificate' et sauvegardé localement temporairement
    kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write -field=certificate pki/root/generate/internal \
        common_name=\"Transcendence Root CA\" \
        ttl=8760h" > ca.crt
        
    if [ -s ca.crt ]; then
        log_success "Root CA généré avec succès."
        
        # 2. Distribution du CA dans Kubernetes
        # Cela permet aux services (Ingress, Pods) de monter ce certificat
        # pour vérifier la validité des connexions TLS internes.
        log_info "Création du secret Kubernetes 'transcendence-ca'..."
        
        kubectl create secret generic transcendence-ca \
            --from-file=ca.crt=ca.crt \
            --dry-run=client -o yaml | kubectl apply -f -
            
        # Nettoyage du fichier temporaire
        rm ca.crt
        log_success "Secret 'transcendence-ca' mis à jour."
    else
        log_error "Échec de la génération du CA (fichier vide)."
        exit 1
    fi
fi

# ==============================================================================
# 4. CONFIGURATION DU RÔLE D'ÉMISSION
# ==============================================================================

log_info "Configuration du rôle d'émission de certificats..."

# Ce rôle définit les règles pour les certificats "feuilles" (Server Certificates)
# qui seront demandés par Nginx ou les microservices.
# - allowed_domains : Liste blanche des domaines signables.
#   -> transcendence.localhost : Pour l'accès navigateur (Ingress)
#   -> svc.cluster.local : Pour les communications internes K8s
# - allow_subdomains : Autorise api.transcendence.localhost, etc.
# - max_ttl : 72h. Force un renouvellement fréquent (Sécurité).

if kubectl exec vault-0 -- sh -c "VAULT_TOKEN=${VAULT_ROOT_TOKEN} vault write pki/roles/transcendence-dot-local \
    allowed_domains=\"transcendence.localhost,svc.cluster.local\" \
    allow_subdomains=true \
    max_ttl=72h" > /dev/null 2>&1; then
    
    log_success "Rôle 'transcendence-dot-local' configuré."
else
    log_error "Impossible de configurer le rôle PKI."
    exit 1
fi