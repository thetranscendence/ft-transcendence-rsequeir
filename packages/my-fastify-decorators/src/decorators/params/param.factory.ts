import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';
import { ParamType, type ParamDefinition } from './param.interfaces.js';

function addParamMetadata(target: object, propertyKey: string | symbol, param: ParamDefinition) {
	const params: ParamDefinition[] =
		Reflect.getOwnMetadata(METADATA_KEYS.param, target, propertyKey) || [];
	params.push(param);
	Reflect.defineMetadata(METADATA_KEYS.param, params, target, propertyKey);
}

export const createParamDecorator =
	(type: ParamType) =>
	(key?: string): ParameterDecorator => {
		return (target, propertyKey, index) => {
			if (!propertyKey) return;
			addParamMetadata(target, propertyKey, { index, type, key });
		};
	};
