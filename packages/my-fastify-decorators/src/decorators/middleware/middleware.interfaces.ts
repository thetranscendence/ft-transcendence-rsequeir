import type { FastifyReply, FastifyRequest } from 'fastify';

export type MiddlewareHandler = (req: FastifyRequest, res: FastifyReply) => void | Promise<void>;

export type MiddlewareClass = new (...args: any[]) => { use: MiddlewareHandler };
