export class BridgeError extends Error {
	constructor(message: string, readonly type: string = "bridge") {
		super(message);
		this.name = "BridgeError";
	}
}

export const UPSTREAM_NOT_FOUND = "bridge.upstream.notfound";

export function isUpstreamNotFound(e: unknown): boolean {
	return e instanceof BridgeError && e.type === UPSTREAM_NOT_FOUND;
}
