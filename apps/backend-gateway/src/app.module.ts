import { Module } from "my-fastify-decorators";
import { AppController } from "./app.controller.js";

@Module({
    controllers: [AppController],
})
export class AppModule {}