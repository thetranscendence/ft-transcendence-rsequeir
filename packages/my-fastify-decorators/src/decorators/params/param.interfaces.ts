export enum ParamType {
	REQ,
	RES,
	BODY,
	QUERY,
	PARAM,
	HEADERS,
	PLUGIN,
}

export interface ParamDefinition {
	index: number;
	type: ParamType;
	key?: string | undefined;
}
