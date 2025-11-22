export interface CanActivateContext<Request = any, Reply = any> {
	req: Request;
	res: Reply;
}

export interface Guard {
	canActivate(context: CanActivateContext): boolean | Promise<boolean>;
}

export type GuardClass = new (...args: any[]) => Guard;
