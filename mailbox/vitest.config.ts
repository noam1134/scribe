import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { defineConfig } from "vitest/config";

// A test-only key; the real one is a `wrangler secret`. Set in the
// environment too, so the required-secret check is satisfied.
const TEST_KEY = "test-key-0123456789abcdef0123456789abcdef";
process.env.MAILBOX_KEY = TEST_KEY;

export default defineConfig({
	plugins: [
		cloudflareTest({
			wrangler: { configPath: "./wrangler.jsonc" },
			miniflare: { bindings: { MAILBOX_KEY: TEST_KEY } },
		}),
	],
});
