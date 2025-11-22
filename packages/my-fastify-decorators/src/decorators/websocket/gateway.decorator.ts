import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export function WebSocketGateway(namespace: string | RegExp = '/'): ClassDecorator {
	return (target: object) => {
		Reflect.defineMetadata(METADATA_KEYS.webSocketGateway, namespace, target);
	};
}
