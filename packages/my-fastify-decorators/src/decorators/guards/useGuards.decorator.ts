import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';
import type { GuardClass } from './guards.interfaces.js';

export function UseGuards(...guards: GuardClass[]): ClassDecorator & MethodDecorator {
	return (target: any, propertyKey?: string | symbol) => {
		if (!propertyKey) {
			const existing: GuardClass[] = Reflect.getOwnMetadata(METADATA_KEYS.guards, target) || [];
			Reflect.defineMetadata(METADATA_KEYS.guards, [...existing, ...guards], target);
			return;
		}
		const existing: GuardClass[] =
			Reflect.getOwnMetadata(METADATA_KEYS.guards, target, propertyKey) || [];
		Reflect.defineMetadata(METADATA_KEYS.guards, [...existing, ...guards], target, propertyKey);
	};
}
