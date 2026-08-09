import { getD1 } from "../../../db";
import { ensureTreasuryAccess, requireTreasuryLeader, TreasuryAccessError, type TreasuryActor } from "../../treasury-access";

type LeaderRow = { email: string; display_name: string; added_by: string; created_at: string };

async function snapshot(db: D1Database, actor: TreasuryActor) {
  const rows = await db.prepare("SELECT * FROM treasury_leaders WHERE faction_id = ? ORDER BY created_at ASC")
    .bind(actor.factionId).all<LeaderRow>();
  return { leaders: rows.results.map((row) => ({ email: row.email, name: row.display_name, addedBy: row.added_by, createdAt: row.created_at })) };
}

export async function GET() {
  try {
    const db = getD1();
    const actor = await requireTreasuryLeader(db);
    return Response.json(await snapshot(db, actor));
  } catch (error) {
    const status = error instanceof TreasuryAccessError ? 403 : 500;
    return Response.json({ error: error instanceof Error ? error.message : "Unable to load access." }, { status });
  }
}

export async function POST(request: Request) {
  try {
    const db = getD1();
    const actor = await requireTreasuryLeader(db);
    await ensureTreasuryAccess(db, actor);
    const payload = await request.json() as Record<string, unknown>;
    const action = String(payload.action ?? "");
    const email = String(payload.email ?? "").trim().toLowerCase();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("Enter a valid email address.");
    if (action === "add") {
      const name = String(payload.name ?? email).trim().slice(0, 80) || email;
      await db.prepare("INSERT OR IGNORE INTO treasury_leaders (faction_id, email, display_name, added_by) VALUES (?, ?, ?, ?)")
        .bind(actor.factionId, email, name, actor.email).run();
    } else if (action === "remove") {
      if (email === actor.email) throw new Error("You cannot remove your own leadership access.");
      const count = await db.prepare("SELECT COUNT(*) AS count FROM treasury_leaders WHERE faction_id = ?")
        .bind(actor.factionId).first<{ count: number }>();
      if ((count?.count ?? 0) <= 1) throw new Error("Keep at least one leadership member.");
      await db.prepare("DELETE FROM treasury_leaders WHERE faction_id = ? AND email = ? COLLATE NOCASE")
        .bind(actor.factionId, email).run();
    } else {
      return Response.json({ error: "Unknown action." }, { status: 400 });
    }
    return Response.json(await snapshot(db, actor));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update access.";
    return Response.json({ error: message }, { status: error instanceof TreasuryAccessError ? 403 : /valid|cannot|keep/i.test(message) ? 400 : 500 });
  }
}
