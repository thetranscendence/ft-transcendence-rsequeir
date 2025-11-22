import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export interface SubscribeMessageDefinition {
	event: string;
	methodName: string | symbol;
}

export function SubscribeMessage(event: string): MethodDecorator {
	return (target: object, propertyKey: string | symbol) => {
		const messages: SubscribeMessageDefinition[] =
			Reflect.getMetadata(METADATA_KEYS.subscribeMessage, target.constructor) || [];

		messages.push({
			event,
			methodName: propertyKey,
		});

		Reflect.defineMetadata(METADATA_KEYS.subscribeMessage, messages, target.constructor);
	};
}
