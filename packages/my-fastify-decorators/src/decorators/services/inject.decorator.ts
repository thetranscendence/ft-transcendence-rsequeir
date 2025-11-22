import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

type InjectableCtor<T = any> = new (...args: any[]) => T;

export function Inject(token: InjectableCtor | any): ParameterDecorator & PropertyDecorator {
	return function (target: any, propertyKey?: string | symbol, parameterIndex?: number) {
		if (typeof parameterIndex === 'number') {
			const ctor = target as Function;
			const paramsMap = Reflect.getMetadata(METADATA_KEYS.injectParams, ctor) || {};
			paramsMap[parameterIndex] = token;
			Reflect.defineMetadata(METADATA_KEYS.injectParams, paramsMap, ctor);
			return;
		}

		if (propertyKey !== undefined) {
			const ctor = typeof target === 'function' ? target : target.constructor;
			const propsMap = Reflect.getMetadata(METADATA_KEYS.injectProps, ctor) || {};
			propsMap[propertyKey] = token;
			Reflect.defineMetadata(METADATA_KEYS.injectProps, propsMap, ctor);
		}
	} as any;
}
