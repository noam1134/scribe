import { createMcpHandler } from "agents/mcp/server";
import { handleApp, notFound } from "./app-api";
import { keyMatches } from "./auth";
import { Mailbox } from "./mailbox";
import { createServer } from "./mcp";

export { Mailbox };

/**
 * Every route lives under the secret key: `/<key>/mcp` for Claude and
 * `/<key>/app/…` for Scribe. Anything else — a wrong or missing key
 * included — is a plain 404.
 */
export default {
	async fetch(request, env, ctx): Promise<Response> {
		const url = new URL(request.url);
		const [, key = "", ...rest] = url.pathname.split("/");
		if (!(await keyMatches(key, env.MAILBOX_KEY))) return notFound();
		const route = rest.join("/").replace(/\/+$/, "");
		const mailbox = env.MAILBOX.getByName("mailbox");

		if (route === "mcp") {
			// The handler serves one exact path; it gets the request without the key.
			const inner = new Request(new URL(`/mcp${url.search}`, url), request);
			const response = await createMcpHandler(() => createServer(mailbox))(inner, env, ctx);
			log("mcp", request.method, response.status);
			return response;
		}
		if (route.startsWith("app/")) {
			const response = await handleApp(request, route.slice("app/".length), mailbox);
			log(route, request.method, response.status);
			return response;
		}
		return notFound();
	},
} satisfies ExportedHandler<Env>;

/** Never logs the path: it holds the key. */
function log(route: string, method: string, status: number): void {
	console.log(JSON.stringify({ event: "request", route, method, status }));
}
