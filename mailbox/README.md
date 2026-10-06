# Scribe mailbox

A small Cloudflare Worker that lets Claude add items to Scribe — from claude.ai on the iPhone, the web or the Mac — while the data stays in iCloud.

The Worker is only a mailbox:

- **Scribe → Worker.** Whenever it syncs, Scribe publishes a snapshot: its categories (in order, with emoji) and what's coming up (overdue tasks and the next 30 days of open tasks and dated memos, titles only).
- **Claude → Worker.** Claude talks MCP to the Worker. It can list the categories, list what's coming up, and queue new items.
- **Worker → Scribe.** Scribe collects the queued items on launch, when it comes to the front, in the iPhone's background refresh and from Settings › Claude › Sync Now. It adds them to its store (iCloud syncs them as usual) and then acknowledges them, which deletes them here.

One deployment is one mailbox: a single Durable Object with SQLite storage.

## Security: the secret link

There is no login. Every route lives under a long random key in the path, compared in constant time with the `MAILBOX_KEY` secret:

| Route | Who | What |
| --- | --- | --- |
| `POST /<key>/mcp` | Claude | MCP over Streamable HTTP (stateless) |
| `PUT /<key>/app/snapshot` | Scribe | the snapshot (JSON, ≤ 512 KB) |
| `GET /<key>/app/inbox` | Scribe | queued items, oldest first; each is leased to the caller for a minute so a second device asking at the same moment doesn't add it too |
| `POST /<key>/app/inbox/ack` | Scribe | `{ "ids": [...] }` of items Scribe added |

A wrong or missing key, an unknown route and an unset (or shorter than 32 characters) `MAILBOX_KEY` all get the same plain `404`. Treat the connector URL like a password: anyone who has it can read your category names and upcoming titles and add items. Request URLs contain the key, so the Worker's invocation logs are off and its own log lines never include the path.

To change the key, put a new secret (below) and paste the new URL into both Claude and Scribe.

## Deploy

Needs Node 20+ and a Cloudflare account.

```sh
cd mailbox
npm ci
npx wrangler login                    # once per machine
openssl rand -hex 32                  # prints the key: keep it (a password manager is a good place)
npx wrangler secret put MAILBOX_KEY   # paste the key at the prompt
npx wrangler deploy
```

`wrangler deploy` refuses to deploy while `MAILBOX_KEY` isn't set (`secrets.required` in `wrangler.jsonc`). If on the very first run `secret put` won't create the Worker, upload the key with the first deploy instead: write `MAILBOX_KEY=<key>` to a file outside the repo, run `npx wrangler deploy --secrets-file <that file>`, then delete the file.

`wrangler deploy` prints the Worker's address, e.g. `https://scribe-mailbox.<your-subdomain>.workers.dev`. The connector URL is that address, the key and `/mcp`:

```
https://scribe-mailbox.<your-subdomain>.workers.dev/<key>/mcp
```

On a custom domain instead of `workers.dev` it works the same way (the MCP handler checks `Host` only on `workers.dev` and localhost).

## Connect Claude

In Claude (claude.ai or the desktop app): **Settings → Connectors → Add custom connector**. Name it "Scribe", paste the connector URL, leave the OAuth fields empty and add it. Connectors added there are available in Claude on the iPhone too.

Claude gets three tools:

- `list_categories` — the category names (+ emoji) from the latest snapshot, its age and the user's local time.
- `list_upcoming` (`days`, default 7, max 30) — overdue tasks, then each day's tasks and dated memos, plus items queued but not collected yet, and how old the snapshot is.
- `add_item` — `title`, `category` (an existing name, matched ignoring case, accents and spaces), `create_category` (to propose a new category), `kind` (`task` or `memo`), `due_date` (`YYYY-MM-DD`), `due_time` (`HH:MM`, 24-hour) and `notes`. An unknown category is refused with the list of real ones, so Claude asks the user. An identical item still waiting isn't queued twice; at most 200 items wait at once.

## Connect Scribe

On the iPhone or the Mac: **Settings → Claude**, paste the **same** connector URL and tap Connect. The link is kept in the iCloud Keychain, so the other device picks it up too. Sync Now collects and publishes at once; Disconnect forgets the link on every device.

## Develop

```sh
npm test               # Vitest in the Workers runtime (@cloudflare/vitest-plugin)
npm run typecheck      # wrangler types + tsc
cp .dev.vars.example .dev.vars   # then put a real key in it
npm run dev            # wrangler dev on http://localhost:8787/<key>/mcp
```

The MCP endpoint uses the Agents SDK's stateless `createMcpHandler` (`agents/mcp/server`) with an MCP SDK v2 server per request, as Cloudflare's docs recommend (`McpAgent` is deprecated). The versions of `agents` and `@modelcontextprotocol/server` are pinned together.
