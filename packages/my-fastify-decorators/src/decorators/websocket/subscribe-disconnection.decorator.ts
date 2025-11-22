import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export function SubscribeDisconnection(): MethodDecorator {
	return (target: object, propertyKey: string | symbol) => {
		Reflect.defineMetadata(METADATA_KEYS.subscribeDisconnection, propertyKey, target.constructor);
	};
}
