import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema } from "../../../db/member-balances";
import { requireScriptSyncActor, ScriptSyncAccessError, scriptSyncErrorResponse } from "../../../db/script-sync";

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
      WHERE faction_id = ? AND member_id = ?
      LIMIT 1`)
      .bind(actor.factionId, actor.memberId).first<BalanceRow>();
    return Response.json({
      member: { id: actor.memberId, name: actor.memberName },
      faction: { id: actor.factionId, name: actor.factionName },
      membershipVerifiedAt: actor.lastVerifiedAt,
      balance: row?.balance ?? 0,
      observedAt: row?.observed_at ?? null,
      updatedAt: row?.updated_at ?? null,
      serverTime: new Date().toISOString(),
    }, { headers: { "cache-control": "no-store" } });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to synchronize the userscript.";
    if (error instanceof ScriptSyncAccessError) {
      return scriptSyncErrorResponse(error);
    }
    return Response.json({ error: message }, { status: 500 });
  }
}
