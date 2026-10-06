import { describe, expect, it } from "vitest";
import { addDays, describeUpcoming, localClock } from "../src/mcp";
import { isCalendarDate, nameKey, type Snapshot } from "../src/model";

// Tue 2026-10-06 23:30 in Jerusalem (UTC+3): still Tuesday there.
const now = new Date("2026-10-06T20:30:00Z");

function stored(upcoming: Snapshot["upcoming"], ageMinutes = 5) {
	return {
		snapshot: {
			version: 1 as const,
			updatedAt: "2026-10-06T20:25:00Z",
			timeZone: "Asia/Jerusalem",
			categories: [{ name: "Work", emoji: "" }],
			upcoming,
		},
		receivedAt: now.getTime() - ageMinutes * 60_000,
	};
}

describe("dates", () => {
	it("reads the clock in the user's time zone", () => {
		expect(localClock(now, "Asia/Jerusalem")).toEqual({ date: "2026-10-06", time: "23:30" });
		expect(localClock(now, "Asia/Bangkok")).toEqual({ date: "2026-10-07", time: "03:30" });
	});

	it("adds days across months and years", () => {
		expect(addDays("2026-10-31", 1)).toBe("2026-11-01");
		expect(addDays("2026-12-31", 1)).toBe("2027-01-01");
		expect(addDays("2026-03-01", -1)).toBe("2026-02-28");
	});

	it("knows real dates", () => {
		expect(isCalendarDate("2028-02-29")).toBe(true);
		expect(isCalendarDate("2026-02-29")).toBe(false);
		expect(isCalendarDate("2026-13-01")).toBe(false);
		expect(isCalendarDate("2026-1-01")).toBe(false);
	});
});

describe("nameKey", () => {
	it("ignores case, accents, width and spaces like Scribe", () => {
		expect(nameKey("Thai Land")).toBe(nameKey("THAILAND"));
		expect(nameKey("Café")).toBe(nameKey("cafe"));
		expect(nameKey("ＷＯＲＫ")).toBe(nameKey("work"));
		expect(nameKey("עבודה")).toBe("עבודה");
		expect(nameKey("Work")).not.toBe(nameKey("Works"));
	});
});

describe("describeUpcoming", () => {
	it("orders like Scribe's agenda: by day, untimed first, then by time", () => {
		const text = describeUpcoming(
			stored([
				{ title: "Late", category: "Work", kind: "task", dueDate: "2026-10-07", dueTime: "18:00" },
				{ title: "Early", category: "Work", kind: "task", dueDate: "2026-10-07", dueTime: "08:00" },
				{ title: "Anytime", category: "Work", kind: "memo", dueDate: "2026-10-07" },
				{ title: "Tonight", category: "Work", kind: "task", dueDate: "2026-10-06" },
			]),
			[],
			7,
			now,
		);
		expect(text).toContain("Tue 2026-10-06 (today):\n- Tonight (task, Work)\n\nWed 2026-10-07 (tomorrow):\n- Anytime (memo, Work)\n- 08:00 Early (task, Work)\n- 18:00 Late (task, Work)");
	});

	it("uses the user's day, not UTC's, for overdue and the window", () => {
		const items: Snapshot["upcoming"] = [
			{ title: "Yesterday", category: "Work", kind: "task", dueDate: "2026-10-05" },
			{ title: "Day 7", category: "Work", kind: "task", dueDate: "2026-10-12" },
			{ title: "Day 8", category: "Work", kind: "task", dueDate: "2026-10-13" },
		];
		const text = describeUpcoming(stored(items), [], 7, now);
		expect(text).toContain("Overdue:\n- Yesterday (task, Work) — was due Mon 2026-10-05");
		expect(text).toContain("Day 7");
		expect(text).not.toContain("Day 8");
	});

	it("warns when the snapshot is over a day old", () => {
		expect(describeUpcoming(stored([], 60 * 30), [], 7, now)).toContain("as of 30 hours ago");
		expect(describeUpcoming(stored([], 60 * 30), [], 7, now)).toContain("hasn't synced for over a day");
		expect(describeUpcoming(stored([], 60 * 24 * 3), [], 7, now)).toContain("as of 3 days ago");
		expect(describeUpcoming(stored([], 5), [], 7, now)).not.toContain("over a day");
	});

	it("says nothing is due for a one-day window", () => {
		expect(describeUpcoming(stored([]), [], 1, now)).toContain("Nothing overdue and nothing due today.");
	});
});
