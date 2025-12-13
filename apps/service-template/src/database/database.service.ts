import { Service } from 'my-fastify-decorators';
import Database from 'better-sqlite3';
import { existsSync, accessSync, constants } from 'fs';
import { join, dirname } from 'path';

/**
 * Service de persistance SQLite.
 * Gère la connexion unique, la configuration WAL et assure le Fail-Fast.
 *
 * Performance : Utilise 'better-sqlite3' (synchrone) pour éviter l'overhead
 * de l'Event Loop sur des opérations locales ultra-rapides.
 */
@Service()
export class DatabaseService {
    /** Instance unique de la connexion SQLite */
    public db: Database.Database;

    /** Nom du service pour le traçage des logs (ex: auth-service) */
    private readonly serviceName: string;

    constructor() {
        this.serviceName = process.env.SERVICE_NAME || 'unknown-service';
        
        // 1. Définition du chemin de la base de données
        // L'injection se fait via les variables d'environnement (Vault/K8s)
        const dbPath = process.env.DB_PATH || join(process.cwd(), 'data', 'service.db');
        const dbFolder = dirname(dbPath);

        // 2. FAIL-FAST : Vérification de l'environnement
        // Nous ne créons PAS le dossier. S'il n'existe pas (mauvais montage PVC), on crash immédiatement.
        this.verifyEnvironment(dbFolder);

        try {
            // 3. Ouverture de la connexion
            this.db = new Database(dbPath, {
                // En DEV, on log les requêtes. En PROD, on évite le bruit.
                verbose: process.env.NODE_ENV === 'development' 
                    ? (msg) => this.logDebug(`Query: ${msg}`) 
                    : undefined,
                // Refuse de créer le fichier si le dossier parent est invalide (sécurité supplémentaire)
                fileMustExist: false, 
            });

            this.logInfo(`Connexion établie avec succès : ${dbPath}`);

            // 4. Optimisation (Performance & Intégrité)
            this.configurePragmas();

        } catch (error) {
            this.logError('Erreur critique lors de l\'ouverture de la base de données', error);
            // Arrêt immédiat du processus. K8s redémarrera le pod, signalant clairement le problème.
            process.exit(1);
        }
    }

    /**
     * Vérifie que le dossier de destination existe et est accessible en écriture.
     * Si ce n'est pas le cas, lève une erreur pour empêcher le démarrage.
     */
    private verifyEnvironment(folderPath: string): void {
        if (!existsSync(folderPath)) {
            const errorMsg = `Le dossier de données '${folderPath}' n'existe pas. Vérifiez le montage du Volume (PVC).`;
            this.logError(errorMsg);
            throw new Error(errorMsg);
        }

        try {
            // Vérifie les droits d'écriture (W_OK) et de lecture (R_OK)
            accessSync(folderPath, constants.R_OK | constants.W_OK);
        } catch (err) {
            const errorMsg = `Le service n'a pas les droits d'écriture sur '${folderPath}'. Vérifiez l'initContainer/chown.`;
            this.logError(errorMsg, err);
            throw new Error(errorMsg);
        }
    }

    /**
     * Applique les configurations optimales pour SQLite en mode serveur.
     */
    private configurePragmas() {
        // WAL (Write-Ahead Logging) : 
        // Permet la concurrence Lecture/Écriture. Évite les goulots d'étranglement.
        this.db.pragma('journal_mode = WAL');

        // FOREIGN_KEYS :
        // Garantit l'intégrité référentielle (ex: impossible de créer un message pour un utilisateur inexistant).
        this.db.pragma('foreign_keys = ON');

        // SYNCHRONOUS = NORMAL :
        // En mode WAL, 'NORMAL' suffit pour garantir l'intégrité même en cas de crash OS,
        // tout en étant beaucoup plus rapide que 'FULL'.
        this.db.pragma('synchronous = NORMAL');
        
        this.logInfo('Configuration SQLite appliquée (WAL, ForeignKeys, Sync).');
    }

    /**
     * Ferme proprement la connexion.
     * À appeler lors du SIGTERM.
     */
    public close() {
        if (this.db && this.db.open) {
            this.logInfo('Fermeture de la connexion SQLite...');
            this.db.close();
        }
    }

    // --- Helpers de Logging Standardisé (Format JSON pour ELK) ---

    private logInfo(message: string) {
        // On utilise process.stdout directement pour garantir un format JSON valide pour Logstash
        console.log(JSON.stringify({
            level: 'info',
            service: this.serviceName,
            component: 'DatabaseService',
            msg: message,
            time: new Date().toISOString()
        }));
    }

    private logDebug(message: string) {
        // En développement seulement
        if (process.env.NODE_ENV === 'development') {
             console.log(JSON.stringify({
                level: 'debug',
                service: this.serviceName,
                component: 'DatabaseService',
                msg: message,
                time: new Date().toISOString()
            }));
        }
    }

    private logError(message: string, error?: unknown) {
        console.error(JSON.stringify({
            level: 'error',
            service: this.serviceName,
            component: 'DatabaseService',
            msg: message,
            error: error instanceof Error ? error.message : error,
            stack: error instanceof Error ? error.stack : undefined,
            time: new Date().toISOString()
        }));
    }
}