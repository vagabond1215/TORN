export type BalanceEvent = {
  eventKey: string;
  memberId?: number;
  memberName: string;
  amount: number;
  kind: "credit" | "payout";
  source: "war" | "oc" | "funds";
  summary: string;
  occurredAt?: string | null;
  explicitBalance?: number;
};

function normalizedObservedAt(value?: string | null) {
  const parsed = Date.parse(value ?? "");
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : new Date().toISOString();
}

export async function ensureMemberBalanceSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS member_balances (
      member_name TEXT PRIMARY KEY COLLATE NOCASE,
      member_id INTEGER,
      balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
      earned_total INTEGER NOT NULL DEFAULT 0 CHECK (earned_total >= 0),
      paid_total INTEGER NOT NULL DEFAULT 0 CHECK (paid_total >= 0),
      observed_at TEXT,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS member_balance_entries (
      event_key TEXT PRIMARY KEY,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      amount INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('credit', 'payout')),
      source TEXT NOT NULL CHECK (source IN ('war', 'oc', 'funds')),
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS payout_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      member_id INTEGER NOT NULL,
      member_name TEXT NOT NULL COLLATE NOCASE,
      amount INTEGER NOT NULL CHECK (amount > 0),
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'paid', 'declined')),
      delivery_preference TEXT NOT NULL DEFAULT 'offline' CHECK (delivery_preference IN ('offline', 'online', 'online_or_travel')),
      note TEXT NOT NULL DEFAULT '',
      requested_by_user_id TEXT NOT NULL,
      requested_by_email TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_member_entries_created ON member_balance_entries(created_at DESC)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_payout_requests_status ON payout_requests(status, created_at DESC)"),
  ]);

  const columns = await db.prepare("PRAGMA table_info(member_balances)").all<{ name: string }>();
  if (!columns.results.some((column) => column.name === "observed_at")) {
    try {
      await db.prepare("ALTER TABLE member_balances ADD COLUMN observed_at TEXT").run();
    } catch (error) {
      if (!/duplicate column/i.test(error instanceof Error ? error.message : String(error))) throw error;
    }
  }
  await db.prepare("UPDATE member_balances SET observed_at = updated_at WHERE observed_at IS NULL").run();
}

export async function recordBalanceEvent(db: D1Database, event: BalanceEvent) {
  const inserted = await db.prepare(`INSERT OR IGNORE INTO member_balance_entries
    (event_key, member_id, member_name, amount, kind, source, summary, occurred_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(event.eventKey, event.memberId ?? null, event.memberName, event.amount, event.kind, event.source, event.summary, event.occurredAt ?? null).run();
  if (!inserted.meta.changes) return;

  const observedAt = normalizedObservedAt(event.occurredAt);
  const isNewer = "member_balances.observed_at IS NULL OR datetime(excluded.observed_at) >= datetime(member_balances.observed_at)";

  if (event.kind === "credit") {
    if (event.explicitBalance !== undefined) {
      await db.prepare(`INSERT INTO member_balances (member_name, member_id, balance, earned_total, observed_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(member_name) DO UPDATE SET
          member_id = COALESCE(excluded.member_id, member_balances.member_id),
          balance = CASE WHEN ${isNewer} THEN excluded.balance ELSE member_balances.balance END,
          earned_total = member_balances.earned_total + excluded.earned_total,
          observed_at = CASE WHEN ${isNewer} THEN excluded.observed_at ELSE member_balances.observed_at END,
          updated_at = CURRENT_TIMESTAMP`)
        .bind(event.memberName, event.memberId ?? null, event.explicitBalance, event.amount, observedAt).run();
    } else {
      await db.prepare(`INSERT INTO member_balances (member_name, member_id, balance, earned_total, observed_at)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(member_name) DO UPDATE SET
          member_id = COALESCE(excluded.member_id, member_balances.member_id),
          balance = CASE WHEN ${isNewer} THEN member_balances.balance + excluded.earned_total ELSE member_balances.balance END,
          earned_total = member_balances.earned_total + excluded.earned_total,
          observed_at = CASE WHEN ${isNewer} THEN excluded.observed_at ELSE member_balances.observed_at END,
          updated_at = CURRENT_TIMESTAMP`)
        .bind(event.memberName, event.memberId ?? null, event.amount, event.amount, observedAt).run();
    }
  } else {
    await db.prepare(`INSERT INTO member_balances (member_name, member_id, balance, paid_total, observed_at)
      VALUES (?, ?, 0, ?, ?)
      ON CONFLICT(member_name) DO UPDATE SET
        member_id = COALESCE(excluded.member_id, member_balances.member_id),
        balance = CASE WHEN ${isNewer} THEN MAX(0, member_balances.balance - excluded.paid_total) ELSE member_balances.balance END,
        paid_total = member_balances.paid_total + excluded.paid_total,
        observed_at = CASE WHEN ${isNewer} THEN excluded.observed_at ELSE member_balances.observed_at END,
        updated_at = CURRENT_TIMESTAMP`)
      .bind(event.memberName, event.memberId ?? null, event.amount, observedAt).run();
  }
}
