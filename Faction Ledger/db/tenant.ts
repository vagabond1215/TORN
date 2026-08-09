export const BLOOD_COVEN_ID = 52984;
export const BLOOD_COVEN_NAME = "Blood Coven";

export type FactionContext = {
  factionId: number;
  factionName: string;
};

export class FactionAccessError extends Error {
  constructor(message: string, public readonly status = 403) {
    super(message);
  }
}

export function bloodCovenContext(): FactionContext {
  return { factionId: BLOOD_COVEN_ID, factionName: BLOOD_COVEN_NAME };
}

export function requireEnabledFaction(factionId: number, factionName: string): FactionContext {
  if (factionId !== BLOOD_COVEN_ID || factionName.trim().toLowerCase() !== BLOOD_COVEN_NAME.toLowerCase()) {
    throw new FactionAccessError(
      factionId
        ? `Faction #${factionId} is not enabled for treasury writes yet.`
        : "An active Torn faction membership is required.",
    );
  }
  return bloodCovenContext();
}

export function rejectFactionOverride(payload: Record<string, unknown>, context: FactionContext) {
  if (!("factionId" in payload) && !("faction_id" in payload)) return;
  const requested = Number(payload.factionId ?? payload.faction_id);
  if (!Number.isSafeInteger(requested) || requested !== context.factionId) {
    throw new FactionAccessError("The requested faction does not match the verified faction session.");
  }
}

export async function ensureFactionFoundation(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS factions (
      faction_id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS faction_members (
      faction_id INTEGER NOT NULL,
      member_id INTEGER NOT NULL,
      member_name TEXT NOT NULL COLLATE NOCASE,
      last_verified_at TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, member_id)
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_faction_members_name ON faction_members(faction_id, member_name COLLATE NOCASE)"),
    db.prepare(`INSERT OR IGNORE INTO factions (faction_id, name, slug) VALUES (?, ?, 'blood-coven')`)
      .bind(BLOOD_COVEN_ID, BLOOD_COVEN_NAME),
  ]);
}

export async function recordVerifiedFactionMember(
  db: D1Database,
  context: FactionContext,
  memberId: number,
  memberName: string,
) {
  await ensureFactionFoundation(db);
  await db.prepare(`INSERT INTO faction_members (faction_id, member_id, member_name, last_verified_at)
    VALUES (?, ?, ?, CURRENT_TIMESTAMP)
    ON CONFLICT(faction_id, member_id) DO UPDATE SET
      member_name = excluded.member_name,
      last_verified_at = excluded.last_verified_at,
      updated_at = CURRENT_TIMESTAMP`)
    .bind(context.factionId, memberId, memberName).run();
}

export async function resolveMemberIdByName(db: D1Database, context: FactionContext, memberName: string) {
  const rows = await db.prepare(`SELECT member_id AS memberId
    FROM faction_members
    WHERE faction_id = ? AND member_name = ? COLLATE NOCASE
    ORDER BY datetime(last_verified_at) DESC
    LIMIT 2`)
    .bind(context.factionId, memberName).all<{ memberId: number }>();
  return rows.results.length === 1 ? rows.results[0].memberId : null;
}
