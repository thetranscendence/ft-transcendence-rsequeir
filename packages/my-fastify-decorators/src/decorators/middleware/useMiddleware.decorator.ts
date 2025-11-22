import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';
import type { MiddlewareClass, MiddlewareHandler } from './middleware.interfaces.js';

export function Middleware(
	...handlers: (MiddlewareClass | MiddlewareHandler)[]
): ClassDecorator & MethodDecorator {
	return (target: any, propertyKey?: string | symbol) => {
		if (!propertyKey) {
			const existing = Reflect.getOwnMetadata(METADATA_KEYS.middlewares, target) || [];
			Reflect.defineMetadata(METADATA_KEYS.middlewares, [...existing, ...handlers], target);
			return;
		}
		const existing = Reflect.getOwnMetadata(METADATA_KEYS.middlewares, target, propertyKey) || [];
		Reflect.defineMetadata(
			METADATA_KEYS.middlewares,
			[...existing, ...handlers],
			target,
			propertyKey,
		);
	};
}
