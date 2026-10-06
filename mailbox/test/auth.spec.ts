import { describe, expect, it } from "vitest";
import { keyMatches } from "../src/auth";
import { call, KEY, putSnapshot, rpc, snapshot } from "./helpers";

describe("keyMatches", () => {
	const key = "a".repeat(64);

	it("matches only the exact key", async () => {
		expect(await keyMatches(key, key)).toBe(true);
		expect(await keyMatches(key.slice(1), key)).toBe(false);
		expect(await keyMatches(`${key}a`, key)).toBe(false);
		expect(await keyMatches("", key)).toBe(false);
	});

	it("matches nothing while the secret is missing or too short", async () => {
		expect(await keyMatches("", undefined)).toBe(false);
		expect(await keyMatches("", "")).toBe(false);
		expect(await keyMatches("short", "short")).toBe(false);
	});
});

describe("the secret link", () => {
	it("opens every route under the right key", async () => {
		expect((await putSnapshot(snapshot())).status).toBe(204);
		expect((await call(`/${KEY}/app/inbox`)).status).toBe(200);
		expect((await rpc("tools/list")).result).toBeDefined();
	});

	it.each([
		["no key", "/app/inbox"],
		["a wrong key", "/0000000000000000000000000000000000000000/app/inbox"],
		["the key with one character changed", `/${KEY.slice(0, -1)}x/app/inbox`],
		["a prefix of the key", `/${KEY.slice(0, 10)}/app/inbox`],
		["the key plus more", `/${KEY}0/app/inbox`],
		["the key in the wrong place", `/app/${KEY}/inbox`],
		["the root", "/"],
	])("is a plain 404 with %s", async (_, path) => {
		const response = await call(path);
		expect(response.status).toBe(404);
		expect(await response.text()).toBe("Not found");
	});

	it("hides MCP behind the key too", async () => {
		const response = await call("/mcp", {
			method: "POST",
			headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
			body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }),
		});
		expect(response.status).toBe(404);
	});

	it("answers an unknown route under the right key like a wrong key", async () => {
		const response = await call(`/${KEY}/admin`);
		expect(response.status).toBe(404);
		expect(await response.text()).toBe("Not found");
	});

	it("tolerates a trailing slash on the MCP path", async () => {
		const response = await call(`/${KEY}/mcp/`, {
			method: "POST",
			headers: { "Content-Type": "application/json", Accept: "application/json, text/event-stream" },
			body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "tools/list", params: {} }),
		});
		expect(response.status).toBe(200);
	});
});
