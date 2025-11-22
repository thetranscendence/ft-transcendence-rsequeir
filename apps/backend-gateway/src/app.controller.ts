import { Controller, Get } from "my-fastify-decorators";

@Controller('/api')
export class AppController {
    @Get('/health')
    healthcheck() {
        return { status: 'ok', service: 'backend-gateway', timestamp: new Date() };
    }

    @Get('/')
    welcome() {
        return { message: 'Welcome to ft_transcendence API Gateway' };
    }
}