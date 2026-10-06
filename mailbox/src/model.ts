import { z } from "zod";

export const LIMITS = {
	title: 500,
	categoryName: 100,
	emoji: 32,
	notes: 5000,
	categories: 300,
	upcoming: 500,
	pendingItems: 200,
	ackIDs: 500,
	snapshotBytes: 512 * 1024,
	ackBytes: 64 * 1024,
} as const;

export const DATE = /^\d{4}-\d{2}-\d{2}$/;
export const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

/** A real calendar day written as YYYY-MM-DD. */
export function isCalendarDate(value: string): boolean {
	if (!DATE.test(value)) return false;
	const [year, month, day] = value.split("-").map(Number) as [number, number, number];
	const date = new Date(Date.UTC(year, month - 1, day));
	return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

export function isClockTime(value: string): boolean {
	return TIME.test(value);
}

export function isTimeZone(value: string): boolean {
	try {
		new Intl.DateTimeFormat("en-US", { timeZone: value });
		return true;
	} catch {
		return false;
	}
}

const trimmed = (max: number) => z.string().trim().min(1).max(max);
const calendarDate = z.string().refine(isCalendarDate, "must be a real date as YYYY-MM-DD");
const clockTime = z.string().refine(isClockTime, "must be a 24-hour time as HH:MM");
export const kind = z.enum(["task", "memo"]);
export type Kind = z.infer<typeof kind>;

/** What the app publishes: its categories and what's coming up. */
export const snapshotSchema = z.object({
	version: z.literal(1),
	updatedAt: z.iso.datetime({ offset: true }),
	timeZone: z.string().refine(isTimeZone, "must be an IANA time zone"),
	categories: z
		.array(z.object({ name: trimmed(LIMITS.categoryName), emoji: z.string().max(LIMITS.emoji).default("") }))
		.max(LIMITS.categories),
	upcoming: z
		.array(
			z.object({
				title: trimmed(LIMITS.title),
				category: z.string().max(LIMITS.categoryName),
				kind,
				dueDate: calendarDate,
				dueTime: clockTime.optional(),
			}),
		)
		.max(LIMITS.upcoming),
});
export type Snapshot = z.infer<typeof snapshotSchema>;
export type UpcomingItem = Snapshot["upcoming"][number];

export const ackSchema = z.object({
	ids: z.array(z.string().min(1).max(64)).max(LIMITS.ackIDs),
});

/** An item Claude queued, as the app collects it. */
export interface InboxItem {
	id: string;
	createdAt: string;
	title: string;
	category: string;
	createCategory: boolean;
	kind: Kind;
	dueDate?: string;
	dueTime?: string;
	notes?: string;
}

export type NewInboxItem = Omit<InboxItem, "id" | "createdAt">;

export interface StoredSnapshot {
	snapshot: Snapshot;
	receivedAt: number;
}

/**
 * The key Scribe compares category names by: case, diacritics, width and
 * whitespace don't count ("Thai Land" = "thailand").
 */
export function nameKey(name: string): string {
	return name.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase().replace(/\s/gu, "");
}
