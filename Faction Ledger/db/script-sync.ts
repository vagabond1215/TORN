export type ScriptSyncActor = {
  tokenId: string;
  memberId: number;
  memberName: string;
};

export class ScriptSyncAccessError extends Error {}

function randomHex(bytes: number) {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

export async function ensureScriptSyncSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS script_sync_tokens (
      token_id TEXT PRIMARY KEY,
      member_id INTEGER NOT NULL,
      member_name TEXT NOT NULL COLLATE NOCASE,
      token_hash TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_used_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      expires_at TEXT NOT NULL DEFAULT (datetime(CURRENT_TIMESTAMP, '+30 days')),
      revoked_at TEXT
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_script_sync_member ON script_sync_tokens(member_id, revoked_at, last_used_at DESC)"),
  ]);
  const columns = await db.prepare("PRAGMA table_info(script_sync_tokens)").all<{ name: string }>();
  if (!columns.results.some((column) => column.name === "expires_at")) {
    try { await db.prepare("ALTER TABLE script_sync_tokens ADD COLUMN expires_at TEXT").run(); }
    catch (error) { if (!/duplicate column/i.test(error instanceof Error ? error.message : String(error))) throw error; }
  }
  await db.prepare("UPDATE script_sync_tokens SET expires_at = datetime(CURRENT_TIMESTAMP, '+30 days') WHERE expires_at IS NULL").run();
}

export async function issueScriptSyncToken(db: D1Database, memberId: number, memberName: string) {
  await ensureScriptSyncSchema(db);
  const tokenId = randomHex(16);
  const secret = randomHex(32);
  const tokenHash = await sha256(secret);
  await db.prepare(`INSERT INTO script_sync_tokens (token_id, member_id, member_name, token_hash, expires_at)
    VALUES (?, ?, ?, ?, datetime(CURRENT_TIMESTAMP, '+30 days'))`)
    .bind(tokenId, memberId, memberName, tokenHash).run();
  return `bc1.${tokenId}.${secret}`;
}

export async function scriptSyncActor(request: Request, db: D1Database): Promise<ScriptSyncActor | null> {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+bc1\.([a-f0-9]{32})\.([a-f0-9]{64})$/i);
  if (!match) return null;
  await ensureScriptSyncSchema(db);
  const tokenHash = await sha256(match[2].toLowerCase());
  const row = await db.prepare(`SELECT token_id AS tokenId, member_id AS memberId, member_name AS memberName
    FROM script_sync_tokens
    WHERE token_id = ? AND token_hash = ? AND revoked_at IS NULL AND datetime(expires_at) > CURRENT_TIMESTAMP`)
    .bind(match[1].toLowerCase(), tokenHash).first<ScriptSyncActor>();
  if (!row) return null;
  await db.prepare("UPDATE script_sync_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE token_id = ?").bind(row.tokenId).run();
  return row;
}

export async function requireScriptSyncActor(request: Request, db: D1Database) {
  const actor = await scriptSyncActor(request, db);
  if (!actor) throw new ScriptSyncAccessError("Reconnect the Blood Coven userscript from the balance page.");
  return actor;
}
