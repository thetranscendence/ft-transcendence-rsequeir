import 'reflect-metadata';
import { METADATA_KEYS } from '../helpers/metadata.keys.js';

type Constructor<T> = new (...args: any[]) => T;

class DIContainer {
	private services: Map<any, any> = new Map();

	public register<T>(token: any, instance: T): void {
		if (!this.services.has(token)) {
			this.services.set(token, instance);
		}
	}

	public resolve<T>(token: Constructor<T>): T {
		if (this.services.has(token)) {
			return this.services.get(token);
		}

		const designParamTypes: Constructor<any>[] =
			Reflect.getMetadata('design:paramtypes', token) || [];
		const injectParamsMap: Record<number, any> =
			Reflect.getMetadata(METADATA_KEYS.injectParams, token) || {};

		const maxArgs = Math.max(
			designParamTypes.length,
			...Object.keys(injectParamsMap).map((k) => Number(k) + 1),
			0,
		);

		const constructorArgs = Array.from({ length: maxArgs }, (_, index) => {
			const depToken = injectParamsMap[index] ?? designParamTypes[index];
			return depToken ? this.resolve(depToken) : undefined;
		});

		const newInstance = new token(...constructorArgs);

		// Apply property injections
		const injectPropsMap: Record<string | symbol, any> =
			Reflect.getMetadata(METADATA_KEYS.injectProps, token) || {};
		for (const [propKey, depToken] of Object.entries(injectPropsMap)) {
			(newInstance as any)[propKey] = this.resolve(depToken);
		}

		this.register(token, newInstance);
		return newInstance;
	}
}

export const container = new DIContainer();
