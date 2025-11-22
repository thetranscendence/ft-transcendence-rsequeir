import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export function SubscribeConnection(): MethodDecorator {
	return (target: object, propertyKey: string | symbol) => {
		Reflect.defineMetadata(METADATA_KEYS.subscribeConnection, propertyKey, target.constructor);
	};
}
