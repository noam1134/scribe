import { env, exports } from "cloudflare:workers";
import { runInDurableObject } from "cloudflare:test";
import type { Mailbox } from "../src/mailbox";
import type { InboxItem, Snapshot } from "../src/model";

export const KEY = env.MAILBOX_KEY;
export const ORIGIN = "http://localhost";

/** Through the Worker's own fetch handler, with the Host header a real request carries. */
export function call(path: string, init: RequestInit = {}): Promise<Response> {
	const headers = new Headers(init.headers);
	headers.set("Host", new URL(ORIGIN).host);
	return exports.default.fetch(`${ORIGIN}${path}`, { ...init, headers });
}

export function putSnapshot(snapshot: unknown): Promise<Response> {
	return call(`/${KEY}/app/snapshot`, {
		method: "PUT",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify(snapshot),
	});
}

export async function getInbox(): Promise<InboxItem[]> {
	const response = await call(`/${KEY}/app/inbox`);
	if (response.status !== 200) throw new Error(`inbox: ${response.status}`);
	return ((await response.json()) as { items: InboxItem[] }).items;
}

export async function ack(ids: string[]): Promise<number> {
	const response = await call(`/${KEY}/app/inbox/ack`, {
		method: "POST",
		headers: { "Content-Type": "application/json" },
		body: JSON.stringify({ ids }),
	});
	if (response.status !== 200) throw new Error(`ack: ${response.status}`);
	return ((await response.json()) as { deleted: number }).deleted;
}

/** Empties the one mailbox (storage is shared by the tests of a file). */
export async function resetMailbox(): Promise<void> {
	await runInDurableObject(env.MAILBOX.getByName("mailbox"), async (_instance: Mailbox, state) => {
		state.storage.sql.exec("DELETE FROM inbox; DELETE FROM snapshot;");
	});
}

/** Ends every lease, as if a minute had passed. */
export async function expireLeases(): Promise<void> {
	await runInDurableObject(env.MAILBOX.getByName("mailbox"), async (_instance: Mailbox, state) => {
		state.storage.sql.exec("UPDATE inbox SET leased_until = 0");
	});
}

export function snapshot(overrides: Partial<Snapshot> = {}): Snapshot {
	return {
		version: 1,
		updatedAt: "2026-10-06T09:00:00Z",
		timeZone: "Asia/Jerusalem",
		categories: [
			{ name: "Work", emoji: "💼" },
			{ name: "Thailand", emoji: "" },
			{ name: "עבודה", emoji: "" },
		],
		upcoming: [],
		...overrides,
	};
}

type JSONRPCResponse = {
	jsonrpc: "2.0";
	id: number;
	result?: Record<string, unknown>;
	error?: { code: number; message: string };
};

let nextID = 1;

/** One JSON-RPC request to the MCP endpoint, as a Streamable HTTP client sends it. */
export async function rpc(method: string, params: Record<string, unknown> = {}): Promise<JSONRPCResponse> {
	const response = await call(`/${KEY}/mcp`, {
		method: "POST",
		headers: {
			"Content-Type": "application/json",
			Accept: "application/json, text/event-stream",
			"MCP-Protocol-Version": "2025-06-18",
		},
		body: JSON.stringify({ jsonrpc: "2.0", id: nextID++, method, params }),
	});
	if (response.status !== 200) throw new Error(`${method}: HTTP ${response.status} ${await response.text()}`);
	const body = await response.text();
	if (response.headers.get("Content-Type")?.includes("text/event-stream")) {
		const data = body
			.split("\n")
			.filter((line) => line.startsWith("data:"))
			.map((line) => JSON.parse(line.slice(5)) as JSONRPCResponse)
			.find((message) => "result" in message || "error" in message);
		if (!data) throw new Error(`${method}: no result in ${body}`);
		return data;
	}
	return JSON.parse(body) as JSONRPCResponse;
}

export type ToolResult = { content: { type: string; text: string }[]; isError?: boolean };

export async function callTool(name: string, args: Record<string, unknown> = {}): Promise<ToolResult & { text: string }> {
	const response = await rpc("tools/call", { name, arguments: args });
	if (response.error) throw new Error(`${name}: ${response.error.message}`);
	const result = response.result as ToolResult;
	return { ...result, text: result.content.map((block) => block.text).join("\n") };
}
