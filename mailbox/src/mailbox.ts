import { DurableObject } from "cloudflare:workers";
import { LIMITS, nameKey, type InboxItem, type NewInboxItem, type Snapshot, type StoredSnapshot } from "./model";

/** How long items handed to one device stay hidden from another. */
export const LEASE_MS = 60_000;

export type EnqueueResult =
	| { status: "queued"; item: InboxItem }
	| { status: "duplicate"; item: InboxItem }
	| { status: "full" };

/**
 * The one mailbox of a deployment: the app's latest snapshot and the items
 * Claude queued until the app collects and acknowledges them.
 */
export class Mailbox extends DurableObject<Env> {
	private readonly sql: SqlStorage;

	constructor(ctx: DurableObjectState, env: Env) {
		super(ctx, env);
		this.sql = ctx.storage.sql;
		this.sql.exec(`
			CREATE TABLE IF NOT EXISTS snapshot (
				id INTEGER PRIMARY KEY CHECK (id = 1),
				body TEXT NOT NULL,
				received_at INTEGER NOT NULL
			);
			CREATE TABLE IF NOT EXISTS inbox (
				id TEXT PRIMARY KEY,
				created_at INTEGER NOT NULL,
				body TEXT NOT NULL,
				leased_until INTEGER NOT NULL DEFAULT 0
			);
		`);
	}

	putSnapshot(snapshot: Snapshot): void {
		this.sql.exec(
			"INSERT OR REPLACE INTO snapshot (id, body, received_at) VALUES (1, ?, ?)",
			JSON.stringify(snapshot),
			Date.now(),
		);
	}

	getSnapshot(): StoredSnapshot | null {
		const row = this.sql.exec<{ body: string; received_at: number }>("SELECT body, received_at FROM snapshot WHERE id = 1").toArray()[0];
		return row ? { snapshot: JSON.parse(row.body) as Snapshot, receivedAt: row.received_at } : null;
	}

	/** An identical item still waiting is returned instead of a second copy (a retried call). */
	enqueue(draft: NewInboxItem): EnqueueResult {
		const pending = this.pending();
		const twin = pending.find((item) => sameItem(item, draft));
		if (twin) return { status: "duplicate", item: twin };
		if (pending.length >= LIMITS.pendingItems) return { status: "full" };
		const now = Date.now();
		const item: InboxItem = { id: crypto.randomUUID(), createdAt: new Date(now).toISOString(), ...draft };
		this.sql.exec("INSERT INTO inbox (id, created_at, body) VALUES (?, ?, ?)", item.id, now, JSON.stringify(item));
		return { status: "queued", item };
	}

	/** Every queued item, oldest first. */
	pending(): InboxItem[] {
		return this.sql
			.exec<{ body: string }>("SELECT body FROM inbox ORDER BY created_at, rowid")
			.toArray()
			.map((row) => JSON.parse(row.body) as InboxItem);
	}

	/**
	 * The items no device is collecting right now, oldest first, leased for
	 * `LEASE_MS` so a second device asking at the same moment doesn't add
	 * them too. Unacknowledged items come back once the lease ends.
	 */
	lease(): InboxItem[] {
		const now = Date.now();
		const rows = this.sql
			.exec<{ id: string; body: string }>("SELECT id, body FROM inbox WHERE leased_until <= ? ORDER BY created_at, rowid", now)
			.toArray();
		for (const row of rows) {
			this.sql.exec("UPDATE inbox SET leased_until = ? WHERE id = ?", now + LEASE_MS, row.id);
		}
		return rows.map((row) => JSON.parse(row.body) as InboxItem);
	}

	/** Returns how many of the ids were still queued. */
	ack(ids: string[]): number {
		let deleted = 0;
		for (const id of new Set(ids)) {
			deleted += this.sql.exec("DELETE FROM inbox WHERE id = ?", id).rowsWritten;
		}
		return deleted;
	}
}

function sameItem(item: InboxItem, draft: NewInboxItem): boolean {
	return (
		nameKey(item.title) === nameKey(draft.title) &&
		nameKey(item.category) === nameKey(draft.category) &&
		item.kind === draft.kind &&
		item.dueDate === draft.dueDate &&
		item.dueTime === draft.dueTime
	);
}
