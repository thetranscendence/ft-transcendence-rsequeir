import 'reflect-metadata'; // Indispensable pour les décorateurs
import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import { bootstrap } from 'my-fastify-decorators';
import { AppModule } from './app.module.js';

async function bootstrapApp() {
    // 1. Initialisation de Fastify (Logger activé pour le dev)
    const app = Fastify({
        logger: true,
    });

    // 2. Sécurité Globale
    // Helmet aide à sécuriser l'app en définissant divers en-têtes HTTP (XSS, HSTS, etc.)
    await app.register(helmet, {
        global: true,
        contentSecurityPolicy: true,
    });

    // 3. Chargement des modules
    bootstrap(app, AppModule);

    // 4. Gestion globale des erreurs (Fail-safe)
    app.setErrorHandler((error: any, request, reply) => {
        app.log.error(error);
        const statusCode = error.statusCode || 500;
        reply.status(statusCode).send({
            statusCode: statusCode,
            message: error.message || 'Internal Server Error'
        });
    });

    // 5. Démarrage
    try {
        const port = 3000;
        await app.listen({ port, host: '0.0.0.0' });
        console.log(`Gateway listening on http://0.0.0.0:${port}`);
    } catch (err) {
        app.log.error(err);
        process.exit(1);
    }
}

bootstrapApp();