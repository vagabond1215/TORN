import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema, recordExplicitBalance } from "../../../db/member-balances";
import { issueScriptSyncToken } from "../../../db/script-sync";
import { recordVerifiedFactionMember, requireEnabledFaction, type FactionContext } from "../../../db/tenant";
import { getChatGPTUser } from "../../chatgpt-auth";
import { requireTreasuryLeader, TreasuryAccessError } from "../../treasury-access";

type JsonObject = Record<string, unknown>;
type BalanceRow = {
  member_name: string;
  member_id: number | null;
  balance: number;
  earned_total: number;
  paid_total: number;
  observed_at: string | null;
  updated_at: string;
};

type VerifiedMember = {
  memberId: number;
  memberName: string;
  factionId: number;
  factionName: string;
};

const TORN_API = "https://api.torn.com/v2";
function asObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {};
}

function asNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : 0;
}

async function tornFetch(path: string, apiKey: string) {
  const response = await fetch(`${TORN_API}${path}?comment=BloodCovenBalanceRequest`, {
    headers: { Authorization: `ApiKey ${apiKey}` }, cache: "no-store",
  });
  const payload = await response.json() as JsonObject;
  const error = asObject(payload.error);
  if (!response.ok || error.error || error.code) throw new Error(String(error.error ?? error.message ?? "Torn API verification failed."));
  return payload;
}

async function verifyMember(apiKey: string): Promise<VerifiedMember> {
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(apiKey)) throw new Error("Enter a valid Torn Public API key.");
  const [basicPayload, factionPayload] = await Promise.all([tornFetch("/user/basic", apiKey), tornFetch("/user/faction", apiKey)]);
  const profile = asObject(basicPayload.profile);
  const faction = asObject(factionPayload.faction);
  const memberId = asNumber(profile.id ?? basicPayload.id);
  const memberName = String(profile.name ?? basicPayload.name ?? "").trim().slice(0, 80);
  const factionId = asNumber(faction.id);
  const factionName = String(faction.name ?? "").trim().slice(0, 100);
  if (!memberId || !memberName) throw new Error("Torn did not return a usable player identity.");
  requireEnabledFaction(factionId, factionName);
  return { memberId, memberName, factionId, factionName };
}

async function memberSnapshot(db: D1Database, context: FactionContext, member: VerifiedMember) {
  await db.prepare(`UPDATE member_balances SET member_id = ?, member_name = ?, resolution_status = 'verified', updated_at = CURRENT_TIMESTAMP
    WHERE id = (SELECT id FROM member_balances WHERE faction_id = ? AND member_id IS NULL AND member_name = ? COLLATE NOCASE ORDER BY id LIMIT 1)
      AND faction_id = ? AND NOT EXISTS (SELECT 1 FROM member_balances WHERE faction_id = ? AND member_id = ?)`)
    .bind(member.memberId, member.memberName, context.factionId, member.memberName, context.factionId, context.factionId, member.memberId).run();
  await db.prepare("UPDATE member_balances SET member_name = ?, resolution_status = 'verified', updated_at = CURRENT_TIMESTAMP WHERE faction_id = ? AND member_id = ?")
    .bind(member.memberName, context.factionId, member.memberId).run();
  const balance = await db.prepare("SELECT * FROM member_balances WHERE faction_id = ? AND member_id = ?")
    .bind(context.factionId, member.memberId).first<BalanceRow>();
  const requests = await db.prepare(`SELECT id, amount, status, note, delivery_preference AS deliveryPreference, created_at AS createdAt, updated_at AS updatedAt
    FROM payout_requests WHERE faction_id = ? AND member_id = ? ORDER BY created_at DESC LIMIT 10`).bind(context.factionId, member.memberId).all();
  const entries = await db.prepare(`SELECT amount, kind, source, summary, occurred_at AS occurredAt, created_at AS createdAt
    FROM member_balance_entries WHERE faction_id = ? AND member_id = ? ORDER BY created_at DESC LIMIT 20`)
    .bind(context.factionId, member.memberId).all();
  return {
    member: { id: member.memberId, name: member.memberName },
    faction: { id: member.factionId, name: member.factionName },
    balance: balance?.balance ?? 0,
    earnedTotal: balance?.earned_total ?? 0,
    paidTotal: balance?.paid_total ?? 0,
    observedAt: balance?.observed_at ?? null,
    updatedAt: balance?.updated_at ?? null,
    requests: requests.results,
    entries: entries.results,
  };
}

export async function GET() {
  try {
    const db = getD1();
    await ensureMemberBalanceSchema(db);
    const actor = await requireTreasuryLeader(db);
    const [balances, requests] = await Promise.all([
      db.prepare("SELECT member_id AS memberId, member_name AS memberName, balance, earned_total AS earnedTotal, paid_total AS paidTotal, observed_at AS observedAt, updated_at AS updatedAt FROM member_balances WHERE faction_id = ? ORDER BY balance DESC, member_name ASC").bind(actor.factionId).all(),
      db.prepare("SELECT id, member_id AS memberId, member_name AS memberName, amount, status, note, delivery_preference AS deliveryPreference, created_at AS createdAt, updated_at AS updatedAt FROM payout_requests WHERE faction_id = ? ORDER BY created_at DESC LIMIT 100").bind(actor.factionId).all(),
    ]);
    return Response.json({ balances: balances.results, requests: requests.results });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unable to load member balances." }, { status: error instanceof TreasuryAccessError ? 403 : 500 });
  }
}

export async function POST(request: Request) {
  try {
    const user = await getChatGPTUser();
    const payload = await request.json() as JsonObject;
    const apiKey = String(payload.apiKey ?? "").trim();
    const member = await verifyMember(apiKey);
    const context = requireEnabledFaction(member.factionId, member.factionName);
    const db = getD1();
    await ensureMemberBalanceSchema(db);
    await recordVerifiedFactionMember(db, context, member.memberId, member.memberName);
    const observedBalance = Number(payload.observedBalance);
    const observedAt = Date.parse(String(payload.observedAt ?? ""));
    if (payload.balanceSource === "armory" && Number.isSafeInteger(observedBalance) && observedBalance >= 0 && observedBalance <= 1_000_000_000_000
      && Number.isFinite(observedAt) && Math.abs(Date.now() - observedAt) <= 7 * 24 * 60 * 60 * 1000) {
      await recordExplicitBalance(db, context, member.memberName, observedBalance, new Date(observedAt).toISOString(), member.memberId);
    }
    const action = String(payload.action ?? "verify");
    if (action === "importSnapshots") {
      const events = Array.isArray(payload.events) ? payload.events.slice(0, 20) : [];
      const acceptedKeys: string[] = [];
      for (const rawEvent of events) {
        const event = asObject(rawEvent);
        const eventKey = String(event.eventKey ?? "").trim();
        const sourceUrl = String(event.sourceUrl ?? "");
        let source: URL;
        try { source = new URL(sourceUrl); } catch { continue; }
        if (!/^[a-z0-9:_-]{8,120}$/i.test(eventKey) || event.eventType !== "member_balance_snapshot" || source.protocol !== "https:" || source.hostname !== "www.torn.com") continue;
        const snapshotObservedAt = Date.parse(String(event.occurredAt ?? ""));
        if (!Number.isFinite(snapshotObservedAt) || snapshotObservedAt > Date.now() + 5 * 60 * 1000) {
          acceptedKeys.push(eventKey);
          continue;
        }
        const snapshotObservedAtIso = new Date(snapshotObservedAt).toISOString();
        const eventPayload = asObject(event.payload);
        const members = Array.isArray(eventPayload.members) ? eventPayload.members.slice(0, 250) : [];
        for (const rawBalance of members) {
          const balanceRow = asObject(rawBalance);
          const name = String(balanceRow.name ?? "").trim().slice(0, 80);
          const balance = Number(balanceRow.balance);
          if (!name || !Number.isSafeInteger(balance) || balance < 0 || balance > 1_000_000_000_000) continue;
          await recordExplicitBalance(db, context, name, balance, snapshotObservedAtIso);
        }
        acceptedKeys.push(eventKey);
      }
      return Response.json({ acceptedKeys, ...(await memberSnapshot(db, context, member)) });
    }
    if (action === "request") {
      const current = await memberSnapshot(db, context, member);
      const amount = asNumber(payload.amount);
      if (amount <= 0 || amount > current.balance) throw new Error("Request an amount up to your available balance.");
      const pending = await db.prepare("SELECT id FROM payout_requests WHERE faction_id = ? AND member_id = ? AND status IN ('pending', 'approved') LIMIT 1")
        .bind(context.factionId, member.memberId).first();
      if (pending) throw new Error("You already have an open payout request.");
      const note = String(payload.note ?? "").trim().slice(0, 160);
      const deliveryPreference = String(payload.deliveryPreference ?? "offline");
      if (!new Set(["offline", "online", "online_or_travel"]).has(deliveryPreference)) throw new Error("Choose a valid delivery preference.");
      await db.prepare(`INSERT INTO payout_requests
        (faction_id, member_id, member_name, amount, delivery_preference, note, requested_by_user_id, requested_by_email)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(context.factionId, member.memberId, member.memberName, amount, deliveryPreference, note, user?.userId ?? "local-member", user?.email ?? "local@blood-coven").run();
    } else if (action !== "verify") {
      return Response.json({ error: "Unknown action." }, { status: 400 });
    }
    const result = await memberSnapshot(db, context, member);
    if (action === "verify" && payload.issueSyncToken === true) {
      return Response.json({
        ...result,
        syncToken: await issueScriptSyncToken(db, member.memberId, member.memberName, member.factionId, member.factionName),
      });
    }
    return Response.json(result);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to verify this balance.";
    return Response.json({ error: message }, { status: /valid|belong|identity|amount|already|preference|Torn|faction/i.test(message) ? 400 : 500 });
  }
}
