import { Controller, Get, HttpCode } from 'my-fastify-decorators';
import { DatabaseService } from './database/database.service.js';
import { performance } from 'perf_hooks';

/**
 * Contrôleur principal de l'application.
 * Gère les routes de diagnostic (Healthcheck) et d'information.
 */
@Controller('/api')
export class AppController {
    private readonly serviceName: string;

    constructor(private dbService: DatabaseService) {
        this.serviceName = process.env.SERVICE_NAME || 'service-template';
    }

    /**
     * Endpoint de Healthcheck (Liveness/Readiness Probe).
     * * SÉCURITÉ :
     * - Ne renvoie jamais de stack trace au client.
     * - Renvoie un code 503 si la DB est inaccessible (le Pod sera retiré du load balancer).
     * * OBSERVABILITÉ :
     * - Mesure la latence de la base de données.
     * * @route GET /api/health
     */
    @Get('/health')
    @HttpCode(200) // Par défaut 200, mais peut être override manuellement
    async healthcheck() {
        const start = performance.now();
        let dbStatus = 'disconnected';
        let latencyMs = 0;

        try {
            // 1. Vérification active : Exécution d'une requête réelle
            // prepare() + get() est synchrone et très rapide (microsecondes)
            const stmt = this.dbService.db.prepare('SELECT 1');
            stmt.get();
            
            const end = performance.now();
            latencyMs = end - start;
            dbStatus = 'connected';

            // Log de flux (Debug seulement pour éviter le spam K8s)
            if (process.env.NODE_ENV === 'development') {
                this.logInfo(`Healthcheck OK. Latency: ${latencyMs.toFixed(3)}ms`);
            }

            return {
                status: 'ok',
                service: this.serviceName,
                database: {
                    status: dbStatus,
                    latency_ms: parseFloat(latencyMs.toFixed(3))
                },
                timestamp: new Date().toISOString(),
                version: process.env.npm_package_version || '0.0.0'
            };

        } catch (err) {
            // LOG CRITIQUE : Seul l'admin voit ceci dans Kibana
            this.logError('Healthcheck FAILED: Database unreachable', err);

            // RÉPONSE SÉCURISÉE : Le client reçoit juste "Service Unavailable"
            // On throw une erreur qui sera attrapée par le Global Error Handler défini dans main.ts
            // Ou on retourne un objet spécifique avec un code 503 explicite.
            const errorResponse = {
                status: 'error',
                service: this.serviceName,
                database: { status: 'disconnected' },
                timestamp: new Date().toISOString()
            };
            
            // Astuce Fastify : On peut renvoyer une erreur HTTP via l'objet réponse standard
            // Mais ici nous retournons l'objet et laissons le framework gérer, 
            // Idéalement, il faudrait injecter @Res() pour set le status 503, 
            // ou lancer une exception standard.
            throw { statusCode: 503, message: 'Service Unavailable', payload: errorResponse };
        }
    }

    /**
     * Route d'accueil publique.
     * @route GET /api/
     */
    @Get('/')
    welcome() {
        this.logInfo('Welcome route accessed');
        return { 
            message: `Welcome to ${this.serviceName} API`,
            docs: '/documentation' // Anticipation Swagger
        };
    }

    // --- Helpers de Logging Standardisé (Format JSON pour ELK) ---
    // Note : Idéalement, ces helpers devraient être dans un LoggerService partagé,
    // mais pour le template, nous les gardons ici pour l'autonomie.

    private logInfo(message: string) {
        console.log(JSON.stringify({
            level: 'info',
            service: this.serviceName,
            component: 'AppController',
            msg: message,
            time: new Date().toISOString()
        }));
    }

    private logError(message: string, error?: unknown) {
        console.error(JSON.stringify({
            level: 'error',
            service: this.serviceName,
            component: 'AppController',
            msg: message,
            error: error instanceof Error ? error.message : error,
            // On n'envoie la stack que si c'est une erreur JS
            stack: error instanceof Error ? error.stack : undefined,
            time: new Date().toISOString()
        }));
    }
}