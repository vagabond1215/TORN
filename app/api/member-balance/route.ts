import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema } from "../../../db/member-balances";
import { getChatGPTUser } from "../../chatgpt-auth";
import { requireTreasuryLeader, TreasuryAccessError } from "../../treasury-access";

type JsonObject = Record<string, unknown>;
type BalanceRow = { member_name: string; member_id: number | null; balance: number; earned_total: number; paid_total: number; updated_at: string };

const TORN_API = "https://api.torn.com/v2";
const BLOOD_COVEN_ID = 52984;

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

async function verifyMember(apiKey: string) {
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(apiKey)) throw new Error("Enter a valid Torn Public API key.");
  const [basicPayload, factionPayload] = await Promise.all([tornFetch("/user/basic", apiKey), tornFetch("/user/faction", apiKey)]);
  const profile = asObject(basicPayload.profile);
  const faction = asObject(factionPayload.faction);
  const memberId = asNumber(profile.id ?? basicPayload.id);
  const memberName = String(profile.name ?? basicPayload.name ?? "").trim().slice(0, 80);
  if (!memberId || !memberName) throw new Error("Torn did not return a usable player identity.");
  if (asNumber(faction.id) !== BLOOD_COVEN_ID || String(faction.name ?? "").trim().toLowerCase() !== "blood coven") {
    throw new Error("This key does not belong to a current Blood Coven member.");
  }
  return { memberId, memberName };
}

async function memberSnapshot(db: D1Database, memberId: number, memberName: string) {
  await db.prepare("UPDATE member_balances SET member_id = ?, updated_at = CURRENT_TIMESTAMP WHERE member_name = ? COLLATE NOCASE")
    .bind(memberId, memberName).run();
  const balance = await db.prepare("SELECT * FROM member_balances WHERE member_name = ? COLLATE NOCASE").bind(memberName).first<BalanceRow>();
  const requests = await db.prepare(`SELECT id, amount, status, note, created_at AS createdAt, updated_at AS updatedAt
    FROM payout_requests WHERE member_id = ? ORDER BY created_at DESC LIMIT 10`).bind(memberId).all();
  const entries = await db.prepare(`SELECT amount, kind, source, summary, occurred_at AS occurredAt, created_at AS createdAt
    FROM member_balance_entries WHERE member_name = ? COLLATE NOCASE ORDER BY created_at DESC LIMIT 20`).bind(memberName).all();
  return {
    member: { id: memberId, name: memberName },
    balance: balance?.balance ?? 0,
    earnedTotal: balance?.earned_total ?? 0,
    paidTotal: balance?.paid_total ?? 0,
    updatedAt: balance?.updated_at ?? null,
    requests: requests.results,
    entries: entries.results,
  };
}

export async function GET() {
  try {
    const db = getD1();
    await ensureMemberBalanceSchema(db);
    await requireTreasuryLeader(db);
    const [balances, requests] = await Promise.all([
      db.prepare("SELECT member_id AS memberId, member_name AS memberName, balance, earned_total AS earnedTotal, paid_total AS paidTotal, updated_at AS updatedAt FROM member_balances ORDER BY balance DESC, member_name ASC").all(),
      db.prepare("SELECT id, member_id AS memberId, member_name AS memberName, amount, status, note, created_at AS createdAt, updated_at AS updatedAt FROM payout_requests ORDER BY created_at DESC LIMIT 100").all(),
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
    const db = getD1();
    await ensureMemberBalanceSchema(db);
    const action = String(payload.action ?? "verify");
    if (action === "request") {
      const current = await memberSnapshot(db, member.memberId, member.memberName);
      const amount = asNumber(payload.amount);
      if (amount <= 0 || amount > current.balance) throw new Error("Request an amount up to your available balance.");
      const pending = await db.prepare("SELECT id FROM payout_requests WHERE member_id = ? AND status IN ('pending', 'approved') LIMIT 1").bind(member.memberId).first();
      if (pending) throw new Error("You already have an open payout request.");
      const note = String(payload.note ?? "").trim().slice(0, 160);
      await db.prepare(`INSERT INTO payout_requests
        (member_id, member_name, amount, note, requested_by_user_id, requested_by_email)
        VALUES (?, ?, ?, ?, ?, ?)`)
        .bind(member.memberId, member.memberName, amount, note, user?.userId ?? "local-member", user?.email ?? "local@blood-coven").run();
    } else if (action !== "verify") {
      return Response.json({ error: "Unknown action." }, { status: 400 });
    }
    return Response.json(await memberSnapshot(db, member.memberId, member.memberName));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to verify this balance.";
    return Response.json({ error: message }, { status: /valid|belong|identity|amount|already|Torn/i.test(message) ? 400 : 500 });
  }
}
