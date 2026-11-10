import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
	plugins: [
		cloudflareTest({
			wrangler: { configPath: "./wrangler.toml" },
			miniflare: {
				// tests read nothing from the network (fetch is mocked) and choose the settings themselves
				bindings: { FLUSH_TOKEN: "test-flush-token", EXTENSIONS_DISCOVERY_MAX: "10" }
			}
		})
	]
});
