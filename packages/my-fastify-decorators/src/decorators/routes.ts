import 'reflect-metadata';
import { METADATA_KEYS } from './helpers/metadata.keys.js';

export type HttpMethod = 'get' | 'post' | 'put' | 'patch' | 'delete';

export interface RouteDefinition {
	path: string;
	method: HttpMethod;
	methodName: string | symbol;
}

const createRouteDecorator =
	(method: HttpMethod) =>
	(path = '/'): MethodDecorator => {
		return (target, propertyKey) => {
			const routes: RouteDefinition[] =
				Reflect.getMetadata(METADATA_KEYS.routes, target.constructor) || [];

			routes.push({
				path,
				method,
				methodName: propertyKey,
			});

			Reflect.defineMetadata(METADATA_KEYS.routes, routes, target.constructor);
		};
	};

export const Get = createRouteDecorator('get');
export const Post = createRouteDecorator('post');
export const Put = createRouteDecorator('put');
export const Patch = createRouteDecorator('patch');
export const Delete = createRouteDecorator('delete');
