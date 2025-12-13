import 'reflect-metadata'; // Indispensable pour l'injection de dépendances
import Fastify, { FastifyInstance } from 'fastify';
import helmet from '@fastify/helmet';
import cors from '@fastify/cors';
import { bootstrap, container } from 'my-fastify-decorators';
import { AppModule } from './app.module.js';
import { DatabaseService } from './database/database.service.js';
import { ServiceError } from './types/service-error.type.js';

/**
 * Point d'entrée du Microservice.
 *
 * RESPONSABILITÉS :
 * 1. Initialisation du serveur Fastify (Logger, Sécurité).
 * 2. Chargement du contexte applicatif (Module racine).
 * 3. Gestion du cycle de vie (Démarrage & Arrêt propre).
 */
async function bootstrapApp() {
    // 1. Initialisation de Fastify
    // Configuration du logger pour être compatible avec ELK (Logstash)
    // En DEV : 'pino-pretty' pour la lisibilité.
    // En PROD : JSON brut pour l'ingestion par Logstash.
    const app: FastifyInstance = Fastify({
        logger: {
            level: process.env.LOG_LEVEL || 'info',
            transport: process.env.NODE_ENV === 'development' ? {
                target: 'pino-pretty',
                options: {
                    translateTime: 'HH:MM:ss Z',
                    ignore: 'pid,hostname',
                },
            } : undefined,
        },
        // Désactive l'en-tête 'X-Powered-By' par sécurité (Security by Obscurity)
        disableRequestLogging: false, 
    });

    try {
        // 2. Middleware de Sécurité
    
      await app.register(helmet, { 
        global: true, 
        contentSecurityPolicy: process.env.NODE_ENV === 'production',
    });

      await app.register(cors, {
          origin: process.env.CORS_ORIGIN || '*', 
          methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
      });

        // 3. Injection de Dépendances (DI)
        // Charge les Contrôleurs et Services définis dans AppModule
        bootstrap(app, AppModule);

        // 4. Gestion Globale des Erreurs (Fail-Safe)
        // On type 'error' en 'unknown' (le standard TS pour les catch blocks)
        // puis on le cast vers notre interface ServiceError.
        app.setErrorHandler((error: unknown, request, reply) => {
            const err = error as ServiceError; // <--- Assertion de type propre

            // Log de l'erreur avec contexte
            request.log.error({ 
                err, // Le logger gère très bien les objets mixtes
                reqId: request.id,
                url: request.url 
            }, 'Unhandled Exception');

            // Accès typé et sécurisé aux propriétés
            const statusCode = err.statusCode || 500;
            // Fallback sur "Unknown Error" si message est undefined
            const message = err.message || 'Internal Server Error';

            // En PROD, on masque les détails des erreurs 500
            const safeMessage = (statusCode === 500 && process.env.NODE_ENV === 'production')
                ? 'Internal Server Error'
                : message;

            reply.status(statusCode).send({
                statusCode,
                error: err.name || 'Error',
                message: safeMessage,
                // On peut inclure le payload si nécessaire (ex: détails de validation)
                payload: err.payload || undefined,
                timestamp: new Date().toISOString()
            });
        });

        // 5. Démarrage du Serveur
        // Le port est injecté par Vault (fichier config sourcé au démarrage du pod)
        const port = parseInt(process.env.API_PORT || '3000', 10);
        const host = '0.0.0.0'; // Requis pour écouter à l'extérieur du conteneur Docker

        await app.listen({ port, host });
        
        const serviceName = process.env.SERVICE_NAME || 'unknown-service';
        app.log.info(`🚀 [${serviceName}] Service listening on ${host}:${port}`);

        // 6. Configuration du Graceful Shutdown
        setupGracefulShutdown(app);

    } catch (err) {
        app.log.fatal(err, 'Failed to start application');
        process.exit(1);
    }
}

/**
 * Configure la gestion des signaux d'arrêt (SIGINT/SIGTERM).
 * Indispensable pour fermer proprement la connexion SQLite (mode WAL)
 * et ne pas perdre de données en cours d'écriture lors d'un redéploiement.
 */
function setupGracefulShutdown(app: FastifyInstance) {
    const shutdown = async (signal: string) => {
        app.log.info(`Received ${signal}. Starting graceful shutdown...`);

        try {
            // A. Fermeture de la base de données
            // On récupère l'instance unique du DatabaseService via le conteneur IOC
            const dbService = container.resolve(DatabaseService);
            if (dbService) {
                dbService.close(); // Ferme la connexion SQLite (Checkpoint WAL)
            } else {
                app.log.warn('DatabaseService not found in container during shutdown.');
            }

            // B. Arrêt du serveur HTTP (refuse les nouvelles connexions)
            await app.close();
            
            app.log.info('Service stopped successfully.');
            process.exit(0);
        } catch (err) {
            app.log.error(err, 'Error during graceful shutdown');
            process.exit(1);
        }
    };

    // SIGINT : Interruption manuelle (Ctrl+C en local)
    process.on('SIGINT', () => shutdown('SIGINT'));
    
    // SIGTERM : Signal d'arrêt standard de Kubernetes (Rolling Update, Scale Down)
    process.on('SIGTERM', () => shutdown('SIGTERM'));
}

// Lancement de l'application
bootstrapApp();