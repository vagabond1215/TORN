import {
  BLOOD_COVEN_ID,
  BLOOD_COVEN_NAME,
  ensureFactionFoundation,
  recordVerifiedFactionMember,
  requireEnabledFaction,
} from "./tenant";
import { ScriptSyncAccessError } from "./script-sync-errors";
export { ScriptSyncAccessError, scriptSyncErrorResponse } from "./script-sync-errors";
export type { ScriptSyncErrorCode } from "./script-sync-errors";

export type ScriptSyncActor = {
  tokenId: string;
  memberId: number;
  memberName: string;
  factionId: number;
  factionName: string;
  lastVerifiedAt: string;
};

type TokenRow = ScriptSyncActor & { tokenHash: string };
type JsonObject = Record<string, unknown>;

const TORN_API = "https://api.torn.com/v2";
const MEMBERSHIP_RECHECK_MS = 5 * 60 * 1000;

function randomHex(bytes: number) {
  const value = new Uint8Array(bytes);
  crypto.getRandomValues(value);
  return Array.from(value, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function asObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {};
}

function asNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : 0;
}

const TORN_CREDENTIAL_ERROR_CODES = new Set([1, 2, 16, 18]);

function unavailableMembership(message: string) {
  return new ScriptSyncAccessError(
    `Unable to reverify Torn membership: ${message}`,
    "membership_check_unavailable",
    503,
  );
}

export async function tornFetch(path: string, apiKey: string) {
  let response: Response;
  try {
    response = await fetch(`${TORN_API}${path}?comment=BloodCovenScriptMembership`, {
      headers: { Authorization: `ApiKey ${apiKey}` },
      cache: "no-store",
    });
  } catch (error) {
    throw unavailableMembership(error instanceof Error ? error.message : "Torn could not be reached.");
  }

  let payload: JsonObject;
  try { payload = await response.json() as JsonObject; }
  catch { throw unavailableMembership(`Torn returned an unreadable response (${response.status}).`); }

  const error = asObject(payload.error);
  if (response.ok && !error.error && !error.code) return payload;

  const errorCode = asNumber(error.code);
  const message = String(error.error ?? error.message ?? `Torn API membership verification failed (${response.status}).`);
  if (response.status >= 500) throw unavailableMembership(message);
  // Official Torn API errors 1/2 are empty/incorrect keys, 16 is insufficient
  // key access, and 18 is a key paused by its owner. Those require user action.
  if (response.status === 401 || TORN_CREDENTIAL_ERROR_CODES.has(errorCode)) {
    throw new ScriptSyncAccessError(
      `Reconnect the userscript API key: ${message}`,
      "membership_revalidation_required",
      401,
    );
  }
  throw unavailableMembership(message);
}

export async function currentTornIdentity(apiKey: string) {
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(apiKey)) {
    throw new ScriptSyncAccessError(
      "Reconnect the userscript with a valid Torn API key.",
      "membership_revalidation_required",
    );
  }
  const [basicPayload, factionPayload] = await Promise.all([
    tornFetch("/user/basic", apiKey),
    tornFetch("/user/faction", apiKey),
  ]);
  const profile = asObject(basicPayload.profile);
  const faction = asObject(factionPayload.faction);
  return {
    memberId: asNumber(profile.id ?? basicPayload.id),
    memberName: String(profile.name ?? basicPayload.name ?? "").trim().slice(0, 80),
    factionId: asNumber(faction.id),
    factionName: String(faction.name ?? "").trim().slice(0, 100),
  };
}

export async function ensureScriptSyncSchema(db: D1Database) {
  await ensureFactionFoundation(db);
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS script_sync_tokens (
      token_id TEXT PRIMARY KEY,
      member_id INTEGER NOT NULL,
      member_name TEXT NOT NULL COLLATE NOCASE,
      faction_id INTEGER NOT NULL,
      faction_name TEXT NOT NULL DEFAULT '',
      token_hash TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_used_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_verified_at TEXT,
      expires_at TEXT,
      revoked_at TEXT,
      revoked_reason TEXT,
      last_queue_depth INTEGER NOT NULL DEFAULT 0,
      last_direct_push_at TEXT
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_script_sync_faction_member ON script_sync_tokens(faction_id, member_id, revoked_at, last_used_at DESC)"),
  ]);
}

export async function issueScriptSyncToken(
  db: D1Database,
  memberId: number,
  memberName: string,
  factionId = BLOOD_COVEN_ID,
  factionName = BLOOD_COVEN_NAME,
) {
  await ensureScriptSyncSchema(db);
  const context = requireEnabledFaction(factionId, factionName);
  await recordVerifiedFactionMember(db, context, memberId, memberName);
  const tokenId = randomHex(16);
  const secret = randomHex(32);
  const tokenHash = await sha256(secret);
  await db.prepare(`INSERT INTO script_sync_tokens
    (token_id, member_id, member_name, faction_id, faction_name, token_hash, last_verified_at, expires_at)
    VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, NULL)`)
    .bind(tokenId, memberId, memberName, context.factionId, context.factionName, tokenHash).run();
  return `bc1.${tokenId}.${secret}`;
}

async function revokeToken(db: D1Database, tokenId: string, factionId: number, reason: string) {
  await db.prepare(`UPDATE script_sync_tokens
    SET revoked_at = CURRENT_TIMESTAMP, revoked_reason = ?
    WHERE token_id = ? AND faction_id = ? AND revoked_at IS NULL`)
    .bind(reason.slice(0, 120), tokenId, factionId).run();
}

export async function scriptSyncActor(request: Request, db: D1Database): Promise<ScriptSyncActor | null> {
  const authorization = request.headers.get("authorization") ?? "";
  const match = authorization.match(/^Bearer\s+bc1\.([a-f0-9]{32})\.([a-f0-9]{64})$/i);
  if (!match) return null;
  await ensureScriptSyncSchema(db);
  const tokenHash = await sha256(match[2].toLowerCase());
  const row = await db.prepare(`SELECT
      token_id AS tokenId,
      member_id AS memberId,
      member_name AS memberName,
      faction_id AS factionId,
      faction_name AS factionName,
      token_hash AS tokenHash,
      COALESCE(last_verified_at, created_at) AS lastVerifiedAt
    FROM script_sync_tokens
    WHERE token_id = ? AND token_hash = ? AND revoked_at IS NULL`)
    .bind(match[1].toLowerCase(), tokenHash).first<TokenRow>();
  if (!row) return null;

  const lastVerified = Date.parse(row.lastVerifiedAt) || 0;
  if (Date.now() - lastVerified >= MEMBERSHIP_RECHECK_MS) {
    const apiKey = String(request.headers.get("x-torn-api-key") ?? "").trim();
    if (!apiKey) {
      throw new ScriptSyncAccessError(
        "Live faction membership must be reverified. Open the balance page and reconnect the userscript.",
        "membership_revalidation_required",
      );
    }

    const current = await currentTornIdentity(apiKey);
    if (!current.memberId || !current.memberName) {
      throw new ScriptSyncAccessError(
        "Torn did not return a usable identity during membership revalidation.",
        "membership_check_unavailable",
        503,
      );
    }
    if (current.memberId !== row.memberId) {
      await revokeToken(db, row.tokenId, row.factionId, `identity changed to ${current.memberId}`);
      throw new ScriptSyncAccessError(
        "This userscript session belongs to a different Torn account and has been signed out.",
        "identity_changed",
        401,
        current.factionId ? { id: current.factionId, name: current.factionName } : null,
      );
    }
    if (current.factionId !== row.factionId) {
      await revokeToken(db, row.tokenId, row.factionId, `faction changed to ${current.factionId || 0}:${current.factionName || "none"}`);
      throw new ScriptSyncAccessError(
        current.factionId
          ? `Torn now reports membership in ${current.factionName || `faction #${current.factionId}`}; the Blood Coven userscript session has been signed out.`
          : "Torn no longer reports an active faction membership; the Blood Coven userscript session has been signed out.",
        "faction_changed",
        401,
        current.factionId ? { id: current.factionId, name: current.factionName } : null,
      );
    }

    const context = requireEnabledFaction(current.factionId, current.factionName);
    await recordVerifiedFactionMember(db, context, current.memberId, current.memberName);

    row.memberName = current.memberName;
    row.factionName = current.factionName || row.factionName;
    row.lastVerifiedAt = new Date().toISOString();
    await db.prepare(`UPDATE script_sync_tokens
      SET member_name = ?, faction_name = ?, last_verified_at = CURRENT_TIMESTAMP, last_used_at = CURRENT_TIMESTAMP
      WHERE token_id = ? AND faction_id = ?`)
      .bind(row.memberName, row.factionName, row.tokenId, row.factionId).run();
  } else {
    await db.prepare("UPDATE script_sync_tokens SET last_used_at = CURRENT_TIMESTAMP WHERE token_id = ? AND faction_id = ?")
      .bind(row.tokenId, row.factionId).run();
  }

  return {
    tokenId: row.tokenId,
    memberId: row.memberId,
    memberName: row.memberName,
    factionId: row.factionId,
    factionName: row.factionName,
    lastVerifiedAt: row.lastVerifiedAt,
  };
}

export async function recordScriptSyncPush(db: D1Database, actor: ScriptSyncActor, queueDepth: number) {
  const safeDepth = Number.isSafeInteger(queueDepth) ? Math.max(0, Math.min(queueDepth, 100_000)) : 0;
  await db.prepare(`UPDATE script_sync_tokens SET
      last_queue_depth = ?, last_direct_push_at = CURRENT_TIMESTAMP, last_used_at = CURRENT_TIMESTAMP
    WHERE token_id = ? AND faction_id = ? AND revoked_at IS NULL`)
    .bind(safeDepth, actor.tokenId, actor.factionId).run();
}

export async function requireScriptSyncActor(request: Request, db: D1Database) {
  const actor = await scriptSyncActor(request, db);
  if (!actor) {
    throw new ScriptSyncAccessError(
      "Reconnect the Blood Coven userscript from the balance page.",
      "invalid_session",
    );
  }
  return actor;
}
