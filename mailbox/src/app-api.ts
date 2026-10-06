import type { z } from "zod";
import type { Mailbox } from "./mailbox";
import { LIMITS, ackSchema, snapshotSchema } from "./model";

type MailboxStub = DurableObjectStub<Mailbox>;

/**
 * The app's side of the mailbox, under `/<key>/app/`:
 * - `PUT snapshot`: categories and what's coming up.
 * - `GET inbox`: queued items, oldest first (leased to the caller for a minute).
 * - `POST inbox/ack`: `{ ids }` the app has added.
 */
export async function handleApp(request: Request, path: string, mailbox: MailboxStub): Promise<Response> {
	try {
		switch (path) {
			case "snapshot": {
				allow(request, "PUT");
				const snapshot = parse(snapshotSchema, await readJSON(request, LIMITS.snapshotBytes));
				await mailbox.putSnapshot(snapshot);
				return new Response(null, { status: 204 });
			}
			case "inbox":
				allow(request, "GET");
				return json({ items: await mailbox.lease() });
			case "inbox/ack": {
				allow(request, "POST");
				const { ids } = parse(ackSchema, await readJSON(request, LIMITS.ackBytes));
				return json({ deleted: await mailbox.ack(ids) });
			}
			default:
				return notFound();
		}
	} catch (error) {
		if (error instanceof HttpError) return json({ error: error.message }, error.status, error.headers);
		throw error;
	}
}

export function notFound(): Response {
	return new Response("Not found", { status: 404 });
}

class HttpError extends Error {
	constructor(
		readonly status: number,
		message: string,
		readonly headers: HeadersInit = {},
	) {
		super(message);
	}
}

function allow(request: Request, method: string): void {
	if (request.method !== method) throw new HttpError(405, `Use ${method}.`, { Allow: method });
}

function parse<T extends z.ZodType>(schema: T, body: unknown): z.infer<T> {
	const result = schema.safeParse(body);
	if (!result.success) {
		const issue = result.error.issues[0];
		const where = issue?.path.length ? `${issue.path.join(".")}: ` : "";
		throw new HttpError(400, `Invalid body — ${where}${issue?.message ?? "unexpected shape"}`);
	}
	return result.data;
}

/** Reads at most `limit` bytes of JSON; the body is streamed so a large one is never buffered whole. */
async function readJSON(request: Request, limit: number): Promise<unknown> {
	const declared = Number(request.headers.get("Content-Length") ?? 0);
	if (declared > limit) throw new HttpError(413, `Body over ${limit} bytes.`);
	if (!request.body) throw new HttpError(400, "Missing body.");
	const reader = request.body.getReader();
	const chunks: Uint8Array[] = [];
	let size = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		size += value.byteLength;
		if (size > limit) {
			await reader.cancel();
			throw new HttpError(413, `Body over ${limit} bytes.`);
		}
		chunks.push(value);
	}
	const bytes = new Uint8Array(size);
	let offset = 0;
	for (const chunk of chunks) {
		bytes.set(chunk, offset);
		offset += chunk.byteLength;
	}
	try {
		return JSON.parse(new TextDecoder().decode(bytes));
	} catch {
		throw new HttpError(400, "Body isn't JSON.");
	}
}

function json(body: unknown, status = 200, headers: HeadersInit = {}): Response {
	return Response.json(body, { status, headers: { "Cache-Control": "no-store", ...Object.fromEntries(new Headers(headers)) } });
}
