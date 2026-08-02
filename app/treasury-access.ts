import { getD1 } from "../db";
import { getChatGPTUser } from "./chatgpt-auth";

export type TreasuryActor = { userId: string; email: string; name: string };

export class TreasuryAccessError extends Error {}

export async function currentTreasuryActor(): Promise<TreasuryActor> {
  const user = await getChatGPTUser();
  return user
    ? { userId: user.userId, email: user.email.toLowerCase(), name: user.displayName }
    : { userId: "local-admin", email: "local@blood-coven", name: "Local administrator" };
}

export async function ensureTreasuryAccess(db: D1Database, actor?: TreasuryActor) {
  await db.prepare(`CREATE TABLE IF NOT EXISTS treasury_leaders (
    email TEXT PRIMARY KEY COLLATE NOCASE,
    display_name TEXT NOT NULL DEFAULT '',
    added_by TEXT NOT NULL DEFAULT '',
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
  )`).run();

  const count = await db.prepare("SELECT COUNT(*) AS count FROM treasury_leaders").first<{ count: number }>();
  if (count?.count) return;

  const transactionColumns = await db.prepare("PRAGMA table_info(transactions)").all<{ name: string }>();
  if (transactionColumns.results.some((column) => column.name === "actor_email")) {
    await db.prepare(`INSERT OR IGNORE INTO treasury_leaders (email, display_name, added_by)
      SELECT LOWER(actor_email), COALESCE(MAX(actor_name), actor_email), 'existing treasury history'
      FROM transactions
      WHERE actor_email IS NOT NULL AND actor_email NOT IN ('', 'system@blood-coven', 'local@blood-coven')
      GROUP BY LOWER(actor_email)`).run();
  }

  const seeded = await db.prepare("SELECT COUNT(*) AS count FROM treasury_leaders").first<{ count: number }>();
  if (!seeded?.count && actor) {
    await db.prepare("INSERT OR IGNORE INTO treasury_leaders (email, display_name, added_by) VALUES (?, ?, ?)")
      .bind(actor.email, actor.name, actor.email).run();
  }
}

export async function requireTreasuryLeader(db = getD1()) {
  const actor = await currentTreasuryActor();
  await ensureTreasuryAccess(db, actor);
  const leader = await db.prepare("SELECT email FROM treasury_leaders WHERE email = ? COLLATE NOCASE").bind(actor.email).first();
  if (!leader) throw new TreasuryAccessError("Leadership access is required.");
  return actor;
}
