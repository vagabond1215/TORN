import { getD1 } from "../db";
import { bloodCovenContext, ensureFactionFoundation, type FactionContext } from "../db/tenant";
import { getChatGPTUser } from "./chatgpt-auth";

export type TreasuryActor = { userId: string; email: string; name: string } & FactionContext;

export class TreasuryAccessError extends Error {}

export async function currentTreasuryActor(): Promise<TreasuryActor> {
  const user = await getChatGPTUser();
  const faction = bloodCovenContext();
  return user
    ? { userId: user.userId, email: user.email.toLowerCase(), name: user.displayName, ...faction }
    : { userId: "local-admin", email: "local@blood-coven", name: "Local administrator", ...faction };
}

export async function ensureTreasuryAccess(db: D1Database, actor?: TreasuryActor) {
  await ensureFactionFoundation(db);
  await db.prepare(`CREATE TABLE IF NOT EXISTS treasury_leaders (
    faction_id INTEGER NOT NULL,
    email TEXT NOT NULL COLLATE NOCASE,
    display_name TEXT NOT NULL DEFAULT '',
    added_by TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (faction_id, email)
  )`).run();

  const context = actor ?? { ...bloodCovenContext(), userId: "system", email: "", name: "" };
  const count = await db.prepare("SELECT COUNT(*) AS count FROM treasury_leaders WHERE faction_id = ?")
    .bind(context.factionId).first<{ count: number }>();
  if (count?.count) return;

  const transactionColumns = await db.prepare("PRAGMA table_info(transactions)").all<{ name: string }>();
  if (transactionColumns.results.some((column) => column.name === "actor_email")) {
    await db.prepare(`INSERT OR IGNORE INTO treasury_leaders (faction_id, email, display_name, added_by)
      SELECT ?, LOWER(actor_email), COALESCE(MAX(actor_name), actor_email), 'existing treasury history'
      FROM transactions
      WHERE faction_id = ? AND actor_email IS NOT NULL AND actor_email NOT IN ('', 'system@blood-coven', 'local@blood-coven')
      GROUP BY LOWER(actor_email)`).bind(context.factionId, context.factionId).run();
  }

  const seeded = await db.prepare("SELECT COUNT(*) AS count FROM treasury_leaders WHERE faction_id = ?")
    .bind(context.factionId).first<{ count: number }>();
  if (!seeded?.count && actor) {
    await db.prepare("INSERT OR IGNORE INTO treasury_leaders (faction_id, email, display_name, added_by) VALUES (?, ?, ?, ?)")
      .bind(actor.factionId, actor.email, actor.name, actor.email).run();
  }
}

export async function requireTreasuryLeader(db = getD1()) {
  const actor = await currentTreasuryActor();
  await ensureTreasuryAccess(db, actor);
  const leader = await db.prepare("SELECT email FROM treasury_leaders WHERE faction_id = ? AND email = ? COLLATE NOCASE")
    .bind(actor.factionId, actor.email).first();
  if (!leader) throw new TreasuryAccessError("Leadership access is required.");
  return actor;
}
