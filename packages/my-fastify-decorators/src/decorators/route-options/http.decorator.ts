import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export function HttpCode(status: number): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		Reflect.defineMetadata(METADATA_KEYS.httpCode, status, target, propertyKey);
	};
}

export function Header(name: string, value: string): ClassDecorator & MethodDecorator {
	return (target: any, propertyKey?: string | symbol) => {
		if (!propertyKey) {
			const existing = Reflect.getOwnMetadata(METADATA_KEYS.headers, target) || {};
			Reflect.defineMetadata(
				METADATA_KEYS.headers,
				{ ...existing, [name.toLowerCase()]: value },
				target,
			);
			return;
		}
		const existing = Reflect.getOwnMetadata(METADATA_KEYS.headers, target, propertyKey) || {};
		Reflect.defineMetadata(
			METADATA_KEYS.headers,
			{ ...existing, [name.toLowerCase()]: value },
			target,
			propertyKey,
		);
	};
}

export function Redirect(url: string, status = 302): MethodDecorator {
	return (target, propertyKey) => {
		if (!propertyKey) return;
		Reflect.defineMetadata(METADATA_KEYS.redirect, { url, status }, target, propertyKey);
	};
}
