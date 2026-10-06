import { McpServer, type CallToolResult } from "@modelcontextprotocol/server";
import { z } from "zod";
import type { Mailbox } from "./mailbox";
import { DATE, LIMITS, TIME, isCalendarDate, kind, nameKey, type InboxItem, type StoredSnapshot, type UpcomingItem } from "./model";

const INSTRUCTIONS = `Scribe is the user's notes-and-tasks app on iPhone and Mac. Every item is a task (something to do) or a memo (something to remember), and lives in one category.
This server is a mailbox: Scribe shares its categories and what's coming up whenever it syncs, and collects the items you add the next time it syncs.
Before adding, match the item to one of the categories from list_categories. When it isn't clear which category fits, ask the user — or ask whether to create a new one — instead of guessing.
Keep titles short and in the user's own words and language (often Hebrew). Add a date or time only when the user gave one, as the user's local day and 24-hour time.`;

type MailboxStub = DurableObjectStub<Mailbox>;

/** A fresh MCP server for one request (the handler is stateless). */
export function createServer(mailbox: MailboxStub, now: () => Date = () => new Date()): McpServer {
	const server = new McpServer({ name: "scribe-mailbox", version: "0.1.0" }, { instructions: INSTRUCTIONS });

	server.registerTool(
		"list_categories",
		{
			title: "List Scribe categories",
			description:
				"List the user's categories in Scribe, in the user's order, with their emoji. Every item goes into exactly one of them. Call this before add_item unless you already know the exact category name.",
			annotations: { readOnlyHint: true, openWorldHint: false },
		},
		async () => text(describeCategories(await mailbox.getSnapshot(), now())),
	);

	server.registerTool(
		"list_upcoming",
		{
			title: "List upcoming Scribe items",
			description:
				"Show what's coming up in Scribe: overdue tasks, then the tasks and dated memos due in the next `days` days (today included), plus items added through Claude that Scribe hasn't collected yet. Scribe shares this list whenever it syncs; the answer says how old it is.",
			inputSchema: z.object({
				days: z.number().int().min(1).max(30).default(7).describe("How many days ahead, today included (1–30, default 7)."),
			}),
			annotations: { readOnlyHint: true, openWorldHint: false },
		},
		async ({ days }) => {
			const [stored, pending] = await Promise.all([mailbox.getSnapshot(), mailbox.pending()]);
			return text(describeUpcoming(stored, pending, days, now()));
		},
	);

	server.registerTool(
		"add_item",
		{
			title: "Add an item to Scribe",
			description:
				"Add a task or memo to Scribe. `category` must be one of the names from list_categories — when it isn't clear which one fits, ask the user first instead of guessing. To file it into a new category the user asked for, pass the new name and create_category: true. The item appears in Scribe the next time the app syncs.",
			inputSchema: z.object({
				title: z.string().trim().min(1).max(LIMITS.title).describe("The item itself, short, in the user's words and language."),
				category: z.string().trim().min(1).max(LIMITS.categoryName).describe("An existing category name from list_categories, or the new name with create_category: true."),
				create_category: z.boolean().default(false).describe("True only when the user wants a new category with this name."),
				kind: kind.default("task").describe("task: something to do (has a checkbox). memo: something to remember."),
				due_date: z
					.string()
					.regex(DATE, "due_date must be YYYY-MM-DD")
					.refine(isCalendarDate, "due_date must be a real date")
					.optional()
					.describe("The user's local day, YYYY-MM-DD. Only when the user gave a date."),
				due_time: z
					.string()
					.regex(TIME, "due_time must be a 24-hour time as HH:MM")
					.optional()
					.describe("24-hour HH:MM on due_date. Only with a due_date."),
				notes: z.string().max(LIMITS.notes).optional().describe("Extra details, shown under the title."),
			}),
			annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
		},
		async (input) => {
			if (input.due_time && !input.due_date) return failure("due_time needs a due_date: pass the day too.");
			const stored = await mailbox.getSnapshot();
			const categories = stored?.snapshot.categories ?? [];
			const existing = categories.find((category) => nameKey(category.name) === nameKey(input.category));
			if (!existing && !input.create_category) {
				return failure(
					stored
						? `Scribe has no category “${input.category}”. Its categories are: ${categories.map((c) => c.name).join(", ") || "none yet"}. Ask the user which one to use, or call again with create_category: true if they want a new category called “${input.category}”.`
						: `Scribe hasn't shared its categories yet, so “${input.category}” can't be checked. Ask the user to open Scribe on their iPhone or Mac (Settings › Claude must hold this connector's link). If they want a new category with that name, call again with create_category: true.`,
				);
			}
			const notes = input.notes?.trim();
			const result = await mailbox.enqueue({
				title: input.title,
				category: existing?.name ?? input.category,
				createCategory: !existing,
				kind: input.kind,
				...(input.due_date ? { dueDate: input.due_date } : {}),
				...(input.due_time ? { dueTime: input.due_time } : {}),
				...(notes ? { notes } : {}),
			});
			switch (result.status) {
				case "full":
					return failure(`Scribe already has ${LIMITS.pendingItems} items waiting to be collected. Ask the user to open Scribe so it can collect them, then try again.`);
				case "duplicate":
					return text(`Already waiting for Scribe: ${describeItem(result.item)}. Nothing new was added.`);
				case "queued": {
					const created = result.item.createCategory ? ` Scribe will create the category “${result.item.category}” for it.` : "";
					return text(`Queued for Scribe: ${describeItem(result.item)}.${created} It appears in Scribe the next time the app syncs (when it's opened, or in the background on the iPhone).`);
				}
			}
		},
	);

	return server;
}

function text(body: string): CallToolResult {
	return { content: [{ type: "text", text: body }] };
}

function failure(body: string): CallToolResult {
	return { content: [{ type: "text", text: body }], isError: true };
}

const NOT_SHARED_YET =
	"Scribe hasn't shared anything yet. Ask the user to open Scribe on their iPhone or Mac and paste this connector's link into Settings › Claude.";

export function describeCategories(stored: StoredSnapshot | null, now: Date): string {
	if (!stored) return `${NOT_SHARED_YET} Until then you can add an item with create_category: true; Scribe files it into that category, creating it if needed.`;
	const { snapshot } = stored;
	const lines = [`Scribe's categories (${freshness(stored, now)}):`];
	if (snapshot.categories.length === 0) {
		lines.push("None yet. Ask the user what to call the first one, then add the item with create_category: true.");
	} else {
		for (const category of snapshot.categories) lines.push(`- ${category.emoji ? `${category.emoji} ` : ""}${category.name}`);
	}
	lines.push(clockLine(snapshot.timeZone, now));
	return lines.join("\n");
}

export function describeUpcoming(stored: StoredSnapshot | null, pending: InboxItem[], days: number, now: Date): string {
	const lines: string[] = [];
	if (!stored) {
		lines.push(NOT_SHARED_YET);
	} else {
		const { snapshot } = stored;
		const today = localClock(now, snapshot.timeZone).date;
		const lastDay = addDays(today, days - 1);
		lines.push(`Scribe ${freshness(stored, now)}. ${clockLine(snapshot.timeZone, now)}`);
		const sorted = [...snapshot.upcoming].sort(byDue);
		const overdue = sorted.filter((item) => item.kind === "task" && item.dueDate < today);
		const coming = sorted.filter((item) => item.dueDate >= today && item.dueDate <= lastDay);
		if (overdue.length === 0 && coming.length === 0) {
			lines.push("", days === 1 ? "Nothing overdue and nothing due today." : `Nothing overdue and nothing due in the next ${days} days.`);
		}
		if (overdue.length > 0) {
			lines.push("", "Overdue:");
			for (const item of overdue) lines.push(`- ${item.title} (${item.kind}, ${item.category}) — was due ${dayLabel(item.dueDate)}${item.dueTime ? ` ${item.dueTime}` : ""}`);
		}
		let currentDay = "";
		for (const item of coming) {
			if (item.dueDate !== currentDay) {
				currentDay = item.dueDate;
				lines.push("", `${dayLabel(currentDay)}${relativeDay(currentDay, today)}:`);
			}
			lines.push(`- ${item.dueTime ? `${item.dueTime} ` : ""}${item.title} (${item.kind}, ${item.category})`);
		}
		if (now.getTime() - stored.receivedAt > 24 * 60 * 60 * 1000) {
			lines.push("", "Note: Scribe hasn't synced for over a day, so this may be out of date. The user can open Scribe to refresh it.");
		}
	}
	if (pending.length > 0) {
		lines.push("", "Added through Claude, not in Scribe yet:");
		for (const item of pending) lines.push(`- ${describeItem(item)}`);
	}
	return lines.join("\n");
}

function describeItem(item: InboxItem): string {
	let due = "";
	if (item.dueDate) due = `, due ${dayLabel(item.dueDate)}${item.dueTime ? ` at ${item.dueTime}` : ""}`;
	return `“${item.title}” (${item.kind}) in ${item.category}${due}`;
}

function freshness(stored: StoredSnapshot, now: Date): string {
	const minutes = Math.max(0, Math.floor((now.getTime() - stored.receivedAt) / 60_000));
	if (minutes < 1) return "as of just now";
	if (minutes < 60) return `as of ${minutes} minute${minutes === 1 ? "" : "s"} ago`;
	const hours = Math.floor(minutes / 60);
	if (hours < 48) return `as of ${hours} hour${hours === 1 ? "" : "s"} ago`;
	return `as of ${Math.floor(hours / 24)} days ago`;
}

function clockLine(timeZone: string, now: Date): string {
	const clock = localClock(now, timeZone);
	return `The user's local time is ${dayLabel(clock.date)} ${clock.time} (${timeZone}).`;
}

export function localClock(now: Date, timeZone: string): { date: string; time: string } {
	const parts: Record<string, string> = {};
	const format = new Intl.DateTimeFormat("en-US", {
		timeZone,
		year: "numeric",
		month: "2-digit",
		day: "2-digit",
		hour: "2-digit",
		minute: "2-digit",
		hourCycle: "h23",
	});
	for (const part of format.formatToParts(now)) parts[part.type] = part.value;
	return { date: `${parts.year}-${parts.month}-${parts.day}`, time: `${parts.hour}:${parts.minute}` };
}

export function addDays(date: string, days: number): string {
	const [year, month, day] = date.split("-").map(Number) as [number, number, number];
	return new Date(Date.UTC(year, month - 1, day + days)).toISOString().slice(0, 10);
}

const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

function dayLabel(date: string): string {
	return `${WEEKDAYS[new Date(`${date}T12:00:00Z`).getUTCDay()]} ${date}`;
}

function relativeDay(date: string, today: string): string {
	if (date === today) return " (today)";
	if (date === addDays(today, 1)) return " (tomorrow)";
	return "";
}

/** The app's agenda order: by day, untimed before timed, then by time. */
function byDue(a: UpcomingItem, b: UpcomingItem): number {
	if (a.dueDate !== b.dueDate) return a.dueDate < b.dueDate ? -1 : 1;
	if (!a.dueTime || !b.dueTime) return (a.dueTime ? 1 : 0) - (b.dueTime ? 1 : 0);
	return a.dueTime < b.dueTime ? -1 : a.dueTime > b.dueTime ? 1 : 0;
}
