import { getD1 } from "../../../db";

type JsonObject = Record<string, unknown>;
type PendingWarRow = {
  war_id: number; faction_id: number; opponent_name: string; started_at: number; ended_at: number; won: number;
  gross_estimate: number; reviewed_value: number | null; status: string; rewards_json: string; members_json: string;
  created_at: string; updated_at: string;
};
type ActiveWarRow = {
  war_id: number; faction_id: number; opponent_name: string; started_at: number; target: number; our_score: number;
  their_score: number; our_chain: number; their_chain: number; members_json: string; updated_at: string;
};
type BaselineRow = { user_id: number; name: string; base_hits: number; base_xanax: number; base_refills: number };
type WarParticipant = { id: number; name: string; score: number; chain: number };
type RankedWar = { war_id: number; start: number; end: number | null; target: number; winner: number | null; factions: WarParticipant[] };

const TORN_API = "https://api.torn.com/v2";
const BLOOD_COVEN = "blood coven";

async function ensureWarSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS pending_wars (
      war_id INTEGER PRIMARY KEY,
      faction_id INTEGER NOT NULL,
      opponent_name TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER NOT NULL,
      won INTEGER NOT NULL DEFAULT 0,
      gross_estimate INTEGER NOT NULL DEFAULT 0,
      reviewed_value INTEGER,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'recorded', 'dismissed')),
      rewards_json TEXT NOT NULL DEFAULT '[]',
      members_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS active_war (
      war_id INTEGER PRIMARY KEY,
      faction_id INTEGER NOT NULL,
      opponent_name TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      target INTEGER NOT NULL DEFAULT 0,
      our_score INTEGER NOT NULL DEFAULT 0,
      their_score INTEGER NOT NULL DEFAULT 0,
      our_chain INTEGER NOT NULL DEFAULT 0,
      their_chain INTEGER NOT NULL DEFAULT 0,
      members_json TEXT NOT NULL DEFAULT '[]',
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS war_member_baselines (
      war_id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      base_hits INTEGER NOT NULL DEFAULT 0,
      base_xanax INTEGER NOT NULL DEFAULT 0,
      base_refills INTEGER NOT NULL DEFAULT 0,
      current_hits INTEGER NOT NULL DEFAULT 0,
      current_xanax INTEGER NOT NULL DEFAULT 0,
      current_refills INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (war_id, user_id)
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_pending_wars_status_end ON pending_wars(status, ended_at DESC)"),
  ]);
}

function asObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {};
}
function asNumber(value: unknown) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : 0;
}
function safeJson<T>(value: string, fallback: T): T {
  try { return JSON.parse(value) as T; } catch { return fallback; }
}

async function tornFetch(path: string, apiKey: string) {
  const separator = path.includes("?") ? "&" : "?";
  const response = await fetch(`${TORN_API}${path}${separator}comment=BloodCovenTreasury`, {
    headers: { Authorization: `ApiKey ${apiKey}` },
    cache: "no-store",
  });
  const payload = await response.json() as JsonObject;
  const error = asObject(payload.error);
  if (!response.ok || error.error || error.code) {
    throw new Error(String(error.error ?? error.message ?? `Torn API request failed (${response.status}).`));
  }
  return payload;
}

function findStat(value: unknown, key: string): number {
  if (Array.isArray(value)) {
    const named = value.find((item) => asObject(item).name === key);
    if (named) return asNumber(asObject(named).value);
    for (const item of value) {
      const nested = findStat(item, key);
      if (nested) return nested;
    }
    return 0;
  }
  const object = asObject(value);
  if (key in object) return asNumber(object[key]);
  for (const nested of Object.values(object)) {
    const found = findStat(nested, key);
    if (found) return found;
  }
  return 0;
}

function pendingWar(row: PendingWarRow) {
  return {
    warId: row.war_id, factionId: row.faction_id, opponentName: row.opponent_name, startedAt: row.started_at,
    endedAt: row.ended_at, won: Boolean(row.won), grossEstimate: row.gross_estimate, reviewedValue: row.reviewed_value,
    status: row.status,
    rewards: safeJson<Array<{ id: number; name: string; quantity: number; marketPrice: number; value: number }>>(row.rewards_json, []),
    members: safeJson<Array<{ id: number; name: string; attacks: number; score: number }>>(row.members_json, []),
    createdAt: row.created_at, updatedAt: row.updated_at,
  };
}
function activeWar(row: ActiveWarRow | null) {
  if (!row) return null;
  return {
    warId: row.war_id, factionId: row.faction_id, opponentName: row.opponent_name, startedAt: row.started_at,
    target: row.target, ourScore: row.our_score, theirScore: row.their_score, ourChain: row.our_chain,
    theirChain: row.their_chain,
    members: safeJson<Array<{ id: number; name: string; hits: number; xanax: number; refills: number; energyEstimate: number }>>(row.members_json, []),
    updatedAt: row.updated_at,
  };
}

async function status(db: D1Database) {
  await ensureWarSchema(db);
  const [pendingResult, active] = await Promise.all([
    db.prepare("SELECT * FROM pending_wars WHERE status = 'pending' ORDER BY ended_at DESC").all<PendingWarRow>(),
    db.prepare("SELECT * FROM active_war ORDER BY updated_at DESC LIMIT 1").first<ActiveWarRow>(),
  ]);
  return { pendingWars: pendingResult.results.map(pendingWar), activeWar: activeWar(active ?? null) };
}

async function importCompletedWar(db: D1Database, apiKey: string, factionId: number, war: RankedWar) {
  if (!war.end || Date.now() / 1000 - war.end > 30 * 86400) return;
  const exists = await db.prepare("SELECT war_id FROM pending_wars WHERE war_id = ?").bind(war.war_id).first();
  if (exists) return;
  const reportResponse = await tornFetch(`/faction/${war.war_id}/rankedwarreport`, apiKey);
  const report = asObject(reportResponse.rankedwarreport);
  const factions = Array.isArray(report.factions) ? report.factions.map(asObject) : [];
  const ours = factions.find((faction) => asNumber(faction.id) === factionId);
  if (!ours) return;
  const opponent = factions.find((faction) => asNumber(faction.id) !== factionId);
  const rewardItems = Array.isArray(asObject(ours.rewards).items) ? (asObject(ours.rewards).items as unknown[]).map(asObject) : [];
  const itemIds = rewardItems.map((item) => asNumber(item.id)).filter(Boolean);
  let itemPrices = new Map<number, number>();
  if (itemIds.length) {
    const itemResponse = await tornFetch(`/torn/${itemIds.join(",")}/items`, apiKey);
    const items = Array.isArray(itemResponse.items) ? itemResponse.items.map(asObject) : [];
    itemPrices = new Map(items.map((item) => [asNumber(item.id), asNumber(asObject(item.value).market_price)]));
  }
  const rewards = rewardItems.map((item) => {
    const id = asNumber(item.id);
    const quantity = asNumber(item.quantity);
    const marketPrice = itemPrices.get(id) ?? 0;
    return { id, name: String(item.name ?? "Reward item"), quantity, marketPrice, value: quantity * marketPrice };
  });
  const grossEstimate = rewards.reduce((sum, item) => sum + item.value, 0);
  const members = (Array.isArray(ours.members) ? ours.members.map(asObject) : []).map((member) => ({
    id: asNumber(member.id), name: String(member.name ?? "Unknown"), attacks: asNumber(member.attacks), score: Number(member.score ?? 0),
  })).sort((a, b) => b.attacks - a.attacks || b.score - a.score);
  await db.prepare(`INSERT OR IGNORE INTO pending_wars
    (war_id, faction_id, opponent_name, started_at, ended_at, won, gross_estimate, rewards_json, members_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(war.war_id, factionId, String(opponent?.name ?? "Unknown faction"), asNumber(report.start) || war.start,
      asNumber(report.end) || war.end, asNumber(report.winner) === factionId ? 1 : 0, grossEstimate,
      JSON.stringify(rewards), JSON.stringify(members)).run();
}

async function memberStats(apiKey: string, userId: number) {
  const response = await tornFetch(`/user/${userId}/personalstats?stat=rankedwarhits,xantaken,refills`, apiKey);
  return {
    hits: findStat(response.personalstats, "rankedwarhits"),
    xanax: findStat(response.personalstats, "xantaken"),
    refills: findStat(response.personalstats, "refills"),
  };
}

async function trackActiveWar(db: D1Database, apiKey: string, factionId: number, war: RankedWar) {
  const ours = war.factions.find((faction) => faction.id === factionId);
  const opponent = war.factions.find((faction) => faction.id !== factionId);
  if (!ours) return;
  const memberResponse = await tornFetch(`/faction/${factionId}/members`, apiKey);
  const members = (Array.isArray(memberResponse.members) ? memberResponse.members : []).map((member) => {
    const object = asObject(member);
    return { id: asNumber(object.id), name: String(object.name ?? "Unknown") };
  }).filter((member) => member.id > 0);
  const existing = await db.prepare("SELECT * FROM war_member_baselines WHERE war_id = ?").bind(war.war_id).all<BaselineRow>();
  const baselineById = new Map(existing.results.map((row) => [row.user_id, row]));
  const tracked: Array<{ id: number; name: string; hits: number; xanax: number; refills: number; energyEstimate: number }> = [];
  for (let index = 0; index < members.length; index += 8) {
    const results = await Promise.all(members.slice(index, index + 8).map(async (member) => ({ member, stats: await memberStats(apiKey, member.id) })));
    for (const { member, stats } of results) {
      const baseline = baselineById.get(member.id);
      const baseHits = baseline?.base_hits ?? stats.hits;
      const baseXanax = baseline?.base_xanax ?? stats.xanax;
      const baseRefills = baseline?.base_refills ?? stats.refills;
      await db.prepare(`INSERT INTO war_member_baselines
        (war_id, user_id, name, base_hits, base_xanax, base_refills, current_hits, current_xanax, current_refills)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(war_id, user_id) DO UPDATE SET name = excluded.name, current_hits = excluded.current_hits,
          current_xanax = excluded.current_xanax, current_refills = excluded.current_refills, updated_at = CURRENT_TIMESTAMP`)
        .bind(war.war_id, member.id, member.name, baseHits, baseXanax, baseRefills, stats.hits, stats.xanax, stats.refills).run();
      const hits = Math.max(0, stats.hits - baseHits);
      const xanax = Math.max(0, stats.xanax - baseXanax);
      const refills = Math.max(0, stats.refills - baseRefills);
      tracked.push({ id: member.id, name: member.name, hits, xanax, refills, energyEstimate: hits * 25 });
    }
  }
  tracked.sort((a, b) => b.hits - a.hits || b.xanax - a.xanax || a.name.localeCompare(b.name));
  await db.prepare(`INSERT INTO active_war
    (war_id, faction_id, opponent_name, started_at, target, our_score, their_score, our_chain, their_chain, members_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(war_id) DO UPDATE SET opponent_name = excluded.opponent_name, target = excluded.target,
      our_score = excluded.our_score, their_score = excluded.their_score, our_chain = excluded.our_chain,
      their_chain = excluded.their_chain, members_json = excluded.members_json, updated_at = CURRENT_TIMESTAMP`)
    .bind(war.war_id, factionId, String(opponent?.name ?? "Unknown faction"), war.start, war.target, ours.score,
      opponent?.score ?? 0, ours.chain, opponent?.chain ?? 0, JSON.stringify(tracked)).run();
  await db.prepare("DELETE FROM active_war WHERE war_id != ?").bind(war.war_id).run();
}

async function sync(db: D1Database, apiKey: string) {
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(apiKey)) throw new Error("Enter a valid Torn API key.");
  const factionResponse = await tornFetch("/user/faction", apiKey);
  const faction = asObject(factionResponse.faction);
  const factionId = asNumber(faction.id);
  const factionName = String(faction.name ?? "").trim();
  if (!factionId || factionName.toLowerCase() !== BLOOD_COVEN) throw new Error("This API key does not belong to a Blood Coven member.");
  const warsResponse = await tornFetch(`/faction/${factionId}/rankedwars?limit=5`, apiKey);
  const wars = (Array.isArray(warsResponse.rankedwars) ? warsResponse.rankedwars.map(asObject) : []).map((war): RankedWar => ({
    war_id: asNumber(war.war_id), start: asNumber(war.start), end: war.end === null ? null : asNumber(war.end),
    target: asNumber(war.target), winner: war.winner === null ? null : asNumber(war.winner),
    factions: (Array.isArray(war.factions) ? war.factions.map(asObject) : []).map((participant) => ({
      id: asNumber(participant.id), name: String(participant.name ?? "Unknown"), score: asNumber(participant.score), chain: asNumber(participant.chain),
    })),
  })).filter((war) => war.war_id > 0);
  for (const war of wars.filter((item) => item.end).slice(0, 3)) await importCompletedWar(db, apiKey, factionId, war);
  const current = wars.find((war) => war.end === null);
  if (current) await trackActiveWar(db, apiKey, factionId, current);
  else await db.prepare("DELETE FROM active_war").run();
  return { ...(await status(db)), faction: { id: factionId, name: factionName }, syncedAt: new Date().toISOString() };
}

export async function GET() {
  try { return Response.json(await status(getD1())); }
  catch (error) { return Response.json({ error: error instanceof Error ? error.message : "Unable to load war tracking." }, { status: 500 }); }
}

export async function POST(request: Request) {
  try {
    const payload = await request.json() as JsonObject;
    const action = String(payload.action ?? "");
    const db = getD1();
    await ensureWarSchema(db);
    if (action === "sync") return Response.json(await sync(db, String(payload.apiKey ?? "").trim()));
    const warId = asNumber(payload.warId);
    if (!warId) throw new Error("Choose a valid war.");
    if (action === "updateEstimate") {
      const amount = asNumber(payload.amount);
      if (amount <= 0) throw new Error("Reviewed value must be greater than zero.");
      await db.prepare("UPDATE pending_wars SET reviewed_value = ?, updated_at = CURRENT_TIMESTAMP WHERE war_id = ? AND status = 'pending'").bind(amount, warId).run();
    } else if (action === "dismiss") {
      await db.prepare("UPDATE pending_wars SET status = 'dismissed', updated_at = CURRENT_TIMESTAMP WHERE war_id = ? AND status = 'pending'").bind(warId).run();
    } else return Response.json({ error: "Unknown action." }, { status: 400 });
    return Response.json(await status(db));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update war tracking.";
    return Response.json({ error: message }, { status: /valid|choose|greater|belong|API key/i.test(message) ? 400 : 500 });
  }
}
