import { beforeEach, describe, expect, it } from "vitest";
import { addDays, localClock } from "../src/mcp";
import { callTool, getInbox, putSnapshot, resetMailbox, rpc, snapshot } from "./helpers";

beforeEach(resetMailbox);

const today = () => localClock(new Date(), "Asia/Jerusalem").date;

describe("MCP server", () => {
	it("initializes with instructions that say to ask about the category", async () => {
		const init = await rpc("initialize", {
			protocolVersion: "2025-06-18",
			capabilities: {},
			clientInfo: { name: "test", version: "1" },
		});
		const result = init.result as { serverInfo: { name: string }; instructions: string };
		expect(result.serverInfo.name).toBe("scribe-mailbox");
		expect(result.instructions).toMatch(/ask the user/);
	});

	it("lists exactly the three tools", async () => {
		const response = await rpc("tools/list");
		const tools = (response.result as { tools: { name: string; inputSchema: { required?: string[] } }[] }).tools;
		expect(tools.map((tool) => tool.name)).toEqual(["list_categories", "list_upcoming", "add_item"]);
		expect(tools.find((tool) => tool.name === "add_item")?.inputSchema.required).toEqual(["title", "category"]);
	});
});

describe("list_categories", () => {
	it("says when Scribe hasn't shared anything", async () => {
		const result = await callTool("list_categories");
		expect(result.isError).toBeFalsy();
		expect(result.text).toMatch(/hasn't shared anything yet/);
	});

	it("lists the categories in order with emoji, the snapshot's age and the user's local time", async () => {
		await putSnapshot(snapshot());
		const { text } = await callTool("list_categories");
		expect(text).toContain("Scribe's categories (as of just now):\n- 💼 Work\n- Thailand\n- עבודה");
		expect(text).toMatch(/The user's local time is \w{3} \d{4}-\d{2}-\d{2} \d{2}:\d{2} \(Asia\/Jerusalem\)\./);
	});

	it("asks for a first category when there are none", async () => {
		await putSnapshot(snapshot({ categories: [] }));
		expect((await callTool("list_categories")).text).toMatch(/None yet/);
	});
});

describe("list_upcoming", () => {
	it("shows overdue tasks, the coming days and items waiting to be collected", async () => {
		const day = today();
		await putSnapshot(
			snapshot({
				upcoming: [
					{ title: "Pay arnona", category: "Work", kind: "task", dueDate: addDays(day, -2) },
					{ title: "Old memo", category: "Work", kind: "memo", dueDate: addDays(day, -1) },
					{ title: "Call Dan", category: "Work", kind: "task", dueDate: day, dueTime: "09:00" },
					{ title: "Passport", category: "Thailand", kind: "memo", dueDate: day },
					{ title: "Flight", category: "Thailand", kind: "task", dueDate: addDays(day, 10) },
				],
			}),
		);
		await callTool("add_item", { title: "Book hotel", category: "Thailand" });

		const week = (await callTool("list_upcoming")).text;
		expect(week).toContain(`Overdue:\n- Pay arnona (task, Work) — was due`);
		expect(week).not.toContain("Old memo");
		expect(week).toMatch(/\(today\):\n- Passport \(memo, Thailand\)\n- 09:00 Call Dan \(task, Work\)/);
		expect(week).not.toContain("Flight");
		expect(week).toContain("Added through Claude, not in Scribe yet:\n- “Book hotel” (task) in Thailand");

		expect((await callTool("list_upcoming", { days: 30 })).text).toContain("Flight (task, Thailand)");
	});

	it("says when nothing is coming up", async () => {
		await putSnapshot(snapshot());
		expect((await callTool("list_upcoming", { days: 3 })).text).toContain("Nothing overdue and nothing due in the next 3 days.");
	});

	it("refuses more than 30 days", async () => {
		const response = await rpc("tools/call", { name: "list_upcoming", arguments: { days: 31 } });
		const failed = response.error !== undefined || (response.result as { isError?: boolean }).isError === true;
		expect(failed).toBe(true);
	});
});

describe("add_item", () => {
	it("queues an item for an existing category, matched loosely and stored by its real name", async () => {
		await putSnapshot(snapshot());
		const result = await callTool("add_item", { title: "  לקנות חלב ", category: "  עבודה", due_date: "2026-10-07" });
		expect(result.isError).toBeFalsy();
		expect(result.text).toContain("Queued for Scribe: “לקנות חלב” (task) in עבודה, due Wed 2026-10-07.");
		expect(result.text).toContain("next time the app syncs");
		const [item] = await getInbox();
		expect(item).toMatchObject({ title: "לקנות חלב", category: "עבודה", createCategory: false, dueDate: "2026-10-07" });
	});

	it("matches case and spacing like Scribe does", async () => {
		await putSnapshot(snapshot({ categories: [{ name: "Thai Land", emoji: "" }] }));
		await callTool("add_item", { title: "Visa", category: "THAILAND" });
		expect((await getInbox())[0]?.category).toBe("Thai Land");
	});

	it("refuses an unknown category and lists the real ones, so Claude asks", async () => {
		await putSnapshot(snapshot());
		const result = await callTool("add_item", { title: "Buy milk", category: "Groceries" });
		expect(result.isError).toBe(true);
		expect(result.text).toContain("Scribe has no category “Groceries”. Its categories are: Work, Thailand, עבודה.");
		expect(result.text).toContain("create_category: true");
		expect(await getInbox()).toEqual([]);
	});

	it("proposes a new category with create_category", async () => {
		await putSnapshot(snapshot());
		const result = await callTool("add_item", { title: "Buy milk", category: "Groceries", create_category: true });
		expect(result.text).toContain("Scribe will create the category “Groceries” for it.");
		expect((await getInbox())[0]).toMatchObject({ category: "Groceries", createCategory: true });
	});

	it("uses the existing category when create_category names one that exists", async () => {
		await putSnapshot(snapshot());
		await callTool("add_item", { title: "Report", category: "work", create_category: true });
		expect((await getInbox())[0]).toMatchObject({ category: "Work", createCategory: false });
	});

	it("before any snapshot, needs create_category", async () => {
		const refused = await callTool("add_item", { title: "Buy milk", category: "Errands" });
		expect(refused.isError).toBe(true);
		expect(refused.text).toMatch(/hasn't shared its categories yet/);
		const queued = await callTool("add_item", { title: "Buy milk", category: "Errands", create_category: true });
		expect(queued.isError).toBeFalsy();
		expect((await getInbox())[0]).toMatchObject({ category: "Errands", createCategory: true });
	});

	it("doesn't queue the same item twice", async () => {
		await putSnapshot(snapshot());
		await callTool("add_item", { title: "Call Dan", category: "Work", due_date: "2026-10-07" });
		const again = await callTool("add_item", { title: "call dan", category: "WORK", due_date: "2026-10-07" });
		expect(again.text).toMatch(/^Already waiting for Scribe/);
		expect(await getInbox()).toHaveLength(1);
	});

	it.each([
		["an empty title", { title: "   ", category: "Work" }],
		["an impossible date", { title: "x", category: "Work", due_date: "2026-02-29" }],
		["a date in another format", { title: "x", category: "Work", due_date: "07/10/2026" }],
		["a 12-hour time", { title: "x", category: "Work", due_date: "2026-10-07", due_time: "9am" }],
		["a time without a date", { title: "x", category: "Work", due_time: "09:00" }],
		["an unknown kind", { title: "x", category: "Work", kind: "event" }],
		["a title over 500 characters", { title: "x".repeat(501), category: "Work" }],
	])("refuses %s", async (_, args) => {
		await putSnapshot(snapshot());
		const response = await rpc("tools/call", { name: "add_item", arguments: args });
		const failed = response.error !== undefined || (response.result as { isError?: boolean }).isError === true;
		expect(failed).toBe(true);
		expect(await getInbox()).toEqual([]);
	});

	it("stops at 200 waiting items", async () => {
		await putSnapshot(snapshot());
		for (let i = 0; i < 200; i++) await callTool("add_item", { title: `Item ${i}`, category: "Work" });
		const result = await callTool("add_item", { title: "One more", category: "Work" });
		expect(result.isError).toBe(true);
		expect(result.text).toMatch(/200 items waiting/);
	});
});
