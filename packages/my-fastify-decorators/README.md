# My Fastify Decorators

Ce package local fournit un ensemble de décorateurs TypeScript permettant de structurer une application **Fastify** avec une architecture orientée **Injection de Dépendances (DI)** et modulaire, fortement inspirée de **NestJS**.

Il permet de conserver les performances de Fastify tout en offrant une organisation de code rigoureuse et maintenable.

## 📦 Installation & Pré-requis

Ce package nécessite `reflect-metadata` pour fonctionner.

```typescript
// Dans votre fichier d'entrée (ex: main.ts)
import 'reflect-metadata'; // DOIT être la première ligne
import Fastify from 'fastify';
import { bootstrap } from 'my-fastify-decorators';
import { AppModule } from './app.module';

const app = Fastify();

// Initialisation de l'application
await bootstrap(app, AppModule);
await app.listen({ port: 3000 });
```

-----

## Modules

L'application est construite comme un graphe de modules. Le décorateur `@Module` définit les métadonnées d'organisation.

```typescript
import { Module } from 'my-fastify-decorators';
import { UserController } from './user.controller';
import { UserService } from './user.service';

@Module({
  imports: [],          // Autres modules requis
  controllers: [UserController], // Contrôleurs gérés par ce module
  providers: [UserService],      // Services injectables
  gateways: []          // Gateways WebSocket
})
export class UserModule {}
```

-----

## 🎮 Contrôleurs (Routing)

Les contrôleurs gèrent les requêtes HTTP entrantes.

### Décorateurs de Méthodes

  * `@Get(path?)`
  * `@Post(path?)`
  * `@Put(path?)`
  * `@Patch(path?)`
  * `@Delete(path?)`

### Décorateurs de Paramètres

Ils permettent d'extraire des données de la requête Fastify :

  * `@Body()` : `req.body`
  * `@Query(key?)` : `req.query` ou une clé spécifique
  * `@Param(key?)` : `req.params`
  * `@Headers(key?)` : `req.headers`
  * `@Req()` : L'objet brut `FastifyRequest`
  * `@Res()` : L'objet brut `FastifyReply`

### Exemple

```typescript
import { Controller, Get, Post, Body, Param } from 'my-fastify-decorators';

@Controller('/users')
export class UserController {
  
  constructor(private userService: UserService) {}

  @Get('/:id')
  async getUser(@Param('id') id: string) {
    return this.userService.findById(id);
  }

  @Post()
  async createUser(@Body() dto: CreateUserDto) {
    return this.userService.create(dto);
  }
}
```

-----

## 💉 Injection de Dépendances (Services)

Le système possède son propre conteneur IOC.

1.  Marquez une classe comme injectable avec `@Service()`.
2.  Injectez-la via le **constructeur** (recommandé) ou via `@Inject`.

```typescript
import { Service } from 'my-fastify-decorators';

@Service()
export class UserService {
  private users = [];

  findAll() {
    return this.users;
  }
}
```

-----

## ✅ Validation (Schémas)

L'intégration utilise le système de validation natif de Fastify (AJV).

  * `@Schema({ body: ..., querystring: ... })` : Définition complète
  * `@BodySchema(jsonSchema)` : Raccourci pour valider le corps
  * `@QuerySchema(jsonSchema)` : Raccourci pour la query string

```typescript
const UserSchema = {
  type: 'object',
  required: ['email'],
  properties: {
    email: { type: 'string', format: 'email' }
  }
};

@Post()
@BodySchema(UserSchema)
create(@Body() body: any) { ... }
```

-----

## 🛡️ Guards & Middlewares

### Guards (Autorisation)

Implémentez l'interface `Guard` pour protéger une route.

```typescript
import { Guard, CanActivateContext, UseGuards } from 'my-fastify-decorators';

@Service()
class AuthGuard implements Guard {
  canActivate(context: CanActivateContext): boolean | Promise<boolean> {
    const { req } = context;
    return !!req.headers.authorization;
  }
}

@Controller('/admin')
@UseGuards(AuthGuard)
export class AdminController { ... }
```

### Middlewares

Pour exécuter du code avant le handler (logging, parsing...).
Utilisez `@Middleware(handler)` sur une classe ou une méthode.

-----

## 🔌 WebSockets (Socket.io)

Le package inclut un support natif pour les passerelles WebSocket via Socket.io.

  * `@WebSocketGateway(namespace)` : Définit une classe comme Gateway.
  * `@SubscribeMessage(event)` : Écoute un événement spécifique.
  * `@SubscribeConnection()` : Déclenché à la connexion d'un client.
  * `@SubscribeDisconnection()` : Déclenché à la déconnexion.
  * `@SocketSchema(schema)` : Valide le payload des messages WebSocket.

```typescript
import { WebSocketGateway, SubscribeMessage } from 'my-fastify-decorators';
import { Socket } from 'socket.io';

@WebSocketGateway('/chat')
export class ChatGateway {
  
  @SubscribeMessage('message')
  handleMessage(socket: Socket, payload: { content: string }) {
    console.log(`Message reçu de ${socket.id}:`, payload);
    return { status: 'ok' }; // Renvoie un ack/réponse à l'émetteur
  }
}
```

-----

## 🚨 Gestion des Erreurs

Des classes d'exceptions HTTP standards sont disponibles pour renvoyer les bons codes d'erreur.

  * `BadRequestException` (400)
  * `UnauthorizedException` (401)
  * `ForbiddenException` (403)
  * `NotFoundException` (404)
  * `ConflictException` (409)
  * `InternalServerErrorException` (500)

```typescript
throw new NotFoundException('Utilisateur introuvable');
```