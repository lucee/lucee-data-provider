declare namespace Cloudflare {
	interface Env extends import("../src/env").Env {}
}

declare module "*?raw" {
	const content: string;
	export default content;
}
