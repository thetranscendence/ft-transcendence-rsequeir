import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

export function Controller(prefix = ''): ClassDecorator {
	return (target: object) => {
		Reflect.defineMetadata(METADATA_KEYS.controller, prefix, target);
	};
}
