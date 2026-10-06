import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { ack, call, callTool, expireLeases, getInbox, KEY, putSnapshot, resetMailbox, snapshot } from "./helpers";

beforeEach(resetMailbox);

const mailbox = () => env.MAILBOX.getByName("mailbox");

describe("PUT snapshot", () => {
	it("stores what the app sends, replacing the last one", async () => {
		expect((await putSnapshot(snapshot())).status).toBe(204);
		const next = snapshot({
			categories: [{ name: "Errands", emoji: "🛒" }],
			upcoming: [{ title: "Buy milk", category: "Errands", kind: "task", dueDate: "2026-10-07", dueTime: "09:30" }],
		});
		expect((await putSnapshot(next)).status).toBe(204);
		const stored = await mailbox().getSnapshot();
		expect(stored?.snapshot).toEqual(next);
		expect(stored?.receivedAt).toBeGreaterThan(0);
	});

	it("fills a missing emoji and trims names", async () => {
		await putSnapshot(snapshot({ categories: [{ name: "  Work " } as { name: string; emoji: string }] }));
		expect((await mailbox().getSnapshot())?.snapshot.categories).toEqual([{ name: "Work", emoji: "" }]);
	});

	it.each([
		["a wrong version", { version: 2 }],
		["a bad time zone", { timeZone: "Mars/Olympus" }],
		["a bad timestamp", { updatedAt: "yesterday" }],
		["an empty category name", { categories: [{ name: " ", emoji: "" }] }],
		["an impossible date", { upcoming: [{ title: "x", category: "Work", kind: "task", dueDate: "2026-02-30" }] }],
		["a bad time", { upcoming: [{ title: "x", category: "Work", kind: "task", dueDate: "2026-10-07", dueTime: "24:00" }] }],
		["an unknown kind", { upcoming: [{ title: "x", category: "Work", kind: "event", dueDate: "2026-10-07" }] }],
		["too many categories", { categories: Array.from({ length: 301 }, (_, i) => ({ name: `C${i}`, emoji: "" })) }],
	])("refuses %s with 400 and keeps the last snapshot", async (_, change) => {
		await putSnapshot(snapshot());
		const response = await putSnapshot({ ...snapshot(), ...change });
		expect(response.status).toBe(400);
		expect(((await response.json()) as { error: string }).error).toMatch(/^Invalid body/);
		expect((await mailbox().getSnapshot())?.snapshot).toEqual(snapshot());
	});

	it("refuses a body that isn't JSON", async () => {
		const response = await call(`/${KEY}/app/snapshot`, { method: "PUT", body: "{nope" });
		expect(response.status).toBe(400);
	});

	it("refuses a body over 512 KB with 413", async () => {
		const response = await call(`/${KEY}/app/snapshot`, { method: "PUT", body: " ".repeat(512 * 1024 + 1) });
		expect(response.status).toBe(413);
	});

	it("refuses other methods with 405", async () => {
		const response = await call(`/${KEY}/app/snapshot`, { method: "POST", body: JSON.stringify(snapshot()) });
		expect(response.status).toBe(405);
		expect(response.headers.get("Allow")).toBe("PUT");
	});
});

describe("inbox", () => {
	it("starts empty", async () => {
		expect(await getInbox()).toEqual([]);
	});

	it("hands out what Claude added, oldest first, until it's acknowledged", async () => {
		await putSnapshot(snapshot());
		await callTool("add_item", { title: "First", category: "Work" });
		await callTool("add_item", { title: "Second", category: "thailand", kind: "memo", due_date: "2026-10-09", due_time: "18:00", notes: "window seat" });

		const items = await getInbox();
		expect(items.map((item) => item.title)).toEqual(["First", "Second"]);
		expect(items[1]).toMatchObject({
			category: "Thailand",
			createCategory: false,
			kind: "memo",
			dueDate: "2026-10-09",
			dueTime: "18:00",
			notes: "window seat",
		});
		expect(items[0]).toMatchObject({ kind: "task", createCategory: false });
		expect(items[0]).not.toHaveProperty("dueDate");
		expect(items[0]?.id).toMatch(/^[0-9a-f-]{36}$/);
		expect(Date.parse(items[0]?.createdAt ?? "")).not.toBeNaN();

		expect(await ack(items.map((item) => item.id))).toBe(2);
		await expireLeases();
		expect(await getInbox()).toEqual([]);
	});

	it("leases items so a second device asking at once gets none, and returns unacknowledged ones later", async () => {
		await putSnapshot(snapshot());
		await callTool("add_item", { title: "Call Dan", category: "Work" });
		const first = await getInbox();
		expect(first).toHaveLength(1);
		expect(await getInbox()).toEqual([]);

		await expireLeases();
		expect((await getInbox()).map((item) => item.id)).toEqual(first.map((item) => item.id));
	});

	it("acknowledges idempotently and ignores unknown ids", async () => {
		await putSnapshot(snapshot());
		await callTool("add_item", { title: "Once", category: "Work" });
		const [item] = await getInbox();
		expect(await ack([item!.id, item!.id, "not-an-id"])).toBe(1);
		expect(await ack([item!.id])).toBe(0);
	});

	it("validates acknowledgements", async () => {
		const send = (body: string) => call(`/${KEY}/app/inbox/ack`, { method: "POST", body });
		expect((await send(JSON.stringify({ ids: "x" }))).status).toBe(400);
		expect((await send(JSON.stringify({ ids: Array.from({ length: 501 }, (_, i) => `${i}`) }))).status).toBe(400);
		expect((await send(JSON.stringify({}))).status).toBe(400);
		expect((await call(`/${KEY}/app/inbox/ack`)).status).toBe(405);
	});

	it("sends no-store responses", async () => {
		const response = await call(`/${KEY}/app/inbox`);
		expect(response.headers.get("Cache-Control")).toBe("no-store");
	});

	it("refuses POST on the inbox", async () => {
		expect((await call(`/${KEY}/app/inbox`, { method: "POST", body: "{}" })).status).toBe(405);
	});
});
