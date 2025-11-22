import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export function SocketSchema(schema: object): MethodDecorator {
	return (target: object, propertyKey: string | symbol) => {
		Reflect.defineMetadata(METADATA_KEYS.schema, schema, target, propertyKey);
	};
}
