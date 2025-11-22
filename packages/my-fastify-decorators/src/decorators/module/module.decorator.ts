import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';
import type { ModuleMetadata } from './module.interfaces.js';

export function Module(metadata: ModuleMetadata): ClassDecorator {
	return (target: object) => {
		Reflect.defineMetadata(METADATA_KEYS.module, metadata, target);
	};
}
