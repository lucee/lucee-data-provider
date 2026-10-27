import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

export default defineConfig({
	plugins: [
		cloudflareTest({
			wrangler: { configPath: "./wrangler.toml" },
			miniflare: {
				// tests choose the R2 settings themselves, independent of the deployed defaults
				bindings: { FLUSH_TOKEN: "test-flush-token", INVALIDATE_TOKEN: "test-invalidate-token", R2_MODE: "off", R2_FILL_ON_MISS: "false", R2_HOSTS: "" }
			}
		})
	]
});
