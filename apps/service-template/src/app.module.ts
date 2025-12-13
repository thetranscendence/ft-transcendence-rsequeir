import { Module } from 'my-fastify-decorators';
import { AppController } from './app.controller.js';
import { DatabaseService } from './database/database.service.js';

/**
 * Module Racine (Root Module) du microservice.
 *
 * RÔLE :
 * - Déclare l'ensemble des composants gérés par le conteneur d'injection de dépendances (DI).
 * - Configure les Contrôleurs (points d'entrée HTTP).
 * - Configure les Providers (services métier, bases de données, etc.).
 *
 * ARCHITECTURE :
 * Ce module est chargé par la fonction `bootstrap` dans `main.ts`.
 * Il instancie le `DatabaseService` (Singleton) et l'injecte dans `AppController`.
 */
@Module({
    // Liste des contrôleurs HTTP à exposer
    controllers: [
        AppController
    ],
    // Liste des services injectables (Singletons par défaut avec @Service)
    providers: [
        DatabaseService
    ],
    // Si besoin d'importer d'autres modules fonctionnels (ex: UserModule, AuthModule)
    imports: [] 
})
export class AppModule {}