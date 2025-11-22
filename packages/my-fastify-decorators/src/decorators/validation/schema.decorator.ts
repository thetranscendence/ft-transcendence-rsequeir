import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export interface RouteSchema {
	body?: unknown;
	querystring?: unknown;
	params?: unknown;
	headers?: unknown;
	response?: Record<number, unknown>;
}

function mergeSchemas(target: object, propertyKey: string | symbol, partial: RouteSchema) {
	const existing: RouteSchema =
		Reflect.getOwnMetadata(METADATA_KEYS.schema, target, propertyKey) || {};
	const merged: RouteSchema = {
		...existing,
		...partial,
		response: { ...(existing.response || {}), ...(partial.response || {}) },
	};
	Reflect.defineMetadata(METADATA_KEYS.schema, merged, target, propertyKey);
}

export function Schema(schema: RouteSchema): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		mergeSchemas(target, propertyKey, schema);
	};
}

export function BodySchema(schema: unknown): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		mergeSchemas(target, propertyKey, { body: schema });
	};
}

export function QuerySchema(schema: unknown): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		mergeSchemas(target, propertyKey, { querystring: schema });
	};
}

export function ParamsSchema(schema: unknown): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		mergeSchemas(target, propertyKey, { params: schema });
	};
}

export function HeadersSchema(schema: unknown): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		mergeSchemas(target, propertyKey, { headers: schema });
	};
}

export function ResponseSchema(status: number, schema: unknown): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		mergeSchemas(target, propertyKey, { response: { [status]: schema } });
	};
}
