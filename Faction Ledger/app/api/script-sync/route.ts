import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema } from "../../../db/member-balances";
import { requireScriptSyncActor, ScriptSyncAccessError } from "../../../db/script-sync";

type BalanceRow = {
  member_id: number | null;
  member_name: string;
  balance: number;
  observed_at: string | null;
  updated_at: string;
};

export async function GET(request: Request) {
  try {
    const db = getD1();
    await ensureMemberBalanceSchema(db);
    const actor = await requireScriptSyncActor(request, db);
    const row = await db.prepare(`SELECT member_id, member_name, balance, observed_at, updated_at
      FROM member_balances
      WHERE member_id = ? OR member_name = ? COLLATE NOCASE
      ORDER BY CASE WHEN member_id = ? THEN 0 ELSE 1 END
      LIMIT 1`)
      .bind(actor.memberId, actor.memberName, actor.memberId).first<BalanceRow>();
    return Response.json({
      member: { id: actor.memberId, name: actor.memberName },
      balance: row?.balance ?? 0,
      observedAt: row?.observed_at ?? null,
      updatedAt: row?.updated_at ?? null,
      serverTime: new Date().toISOString(),
    }, { headers: { "cache-control": "no-store" } });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to synchronize the userscript.";
    return Response.json({ error: message }, { status: error instanceof ScriptSyncAccessError ? 401 : 500 });
  }
}
