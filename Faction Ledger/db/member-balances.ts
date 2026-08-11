import type { FactionContext } from "./tenant";
import { ensureFactionFoundation, resolveMemberIdByName } from "./tenant";

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

export type BalanceObservation = {
  eventKey: string;
  memberId?: number;
  memberName: string;
  oldBalance: number;
  newBalance: number;
  direction: "increase" | "decrease";
  summary: string;
  occurredAt?: string | null;
};

type BalanceRow = {
  id: number;
  member_id: number | null;
  member_name: string;
  balance: number;
  earned_total: number;
  paid_total: number;
  observed_at: string | null;
  observed_priority: number;
};

const applyMemberBalanceEntryTrigger = `CREATE TRIGGER IF NOT EXISTS apply_member_balance_entry
  AFTER INSERT ON member_balance_entries
  BEGIN
    SELECT CASE WHEN NEW.member_id IS NULL AND (
      SELECT COUNT(*) FROM member_balances
      WHERE faction_id = NEW.faction_id AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE
    ) > 1 THEN RAISE(ABORT, 'ambiguous member balance identity') END;

    UPDATE member_balances SET
      member_id = NEW.member_id,
      member_name = NEW.member_name,
      resolution_status = 'verified',
      updated_at = CURRENT_TIMESTAMP
    WHERE NEW.member_id IS NOT NULL
      AND id = (
        SELECT MIN(id) FROM member_balances
        WHERE faction_id = NEW.faction_id AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE
        HAVING COUNT(*) = 1
      )
      AND NOT EXISTS (
        SELECT 1 FROM member_balances WHERE faction_id = NEW.faction_id AND member_id = NEW.member_id
      );

    INSERT INTO member_balances
      (faction_id, member_id, member_name, balance, earned_total, paid_total, resolution_status)
    SELECT NEW.faction_id, NEW.member_id, NEW.member_name, 0, 0, 0, 'verified'
    WHERE NEW.member_id IS NOT NULL
    ON CONFLICT(faction_id, member_id) WHERE member_id IS NOT NULL DO UPDATE SET
      member_name = excluded.member_name,
      resolution_status = 'verified',
      updated_at = CURRENT_TIMESTAMP;

    INSERT INTO member_balances
      (faction_id, member_id, member_name, balance, earned_total, paid_total, resolution_status)
    SELECT NEW.faction_id, NULL, NEW.member_name, 0, 0, 0, 'unresolved'
    WHERE NEW.member_id IS NULL AND NOT EXISTS (
      SELECT 1 FROM member_balances
      WHERE faction_id = NEW.faction_id AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE
    );

    UPDATE member_balances SET
      member_name = NEW.member_name,
      balance = CASE WHEN
        observed_at IS NULL
        OR julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) > julianday(observed_at)
        OR (
          julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) = julianday(observed_at)
          AND CASE WHEN NEW.explicit_balance IS NULL THEN 1 ELSE 2 END >= observed_priority
        )
      THEN CASE
        WHEN NEW.kind = 'credit' AND NEW.explicit_balance IS NOT NULL THEN MAX(0, NEW.explicit_balance)
        WHEN NEW.kind = 'credit' THEN MAX(0, balance + NEW.amount)
        ELSE MAX(0, balance - NEW.amount)
      END ELSE balance END,
      earned_total = earned_total + CASE WHEN NEW.kind = 'credit' THEN NEW.amount ELSE 0 END,
      paid_total = paid_total + CASE WHEN NEW.kind = 'payout' THEN NEW.amount ELSE 0 END,
      observed_at = CASE WHEN
        observed_at IS NULL
        OR julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) > julianday(observed_at)
        OR (
          julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) = julianday(observed_at)
          AND CASE WHEN NEW.explicit_balance IS NULL THEN 1 ELSE 2 END >= observed_priority
        )
      THEN COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP) ELSE observed_at END,
      observed_priority = CASE WHEN
        observed_at IS NULL
        OR julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) > julianday(observed_at)
        OR (
          julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) = julianday(observed_at)
          AND CASE WHEN NEW.explicit_balance IS NULL THEN 1 ELSE 2 END >= observed_priority
        )
      THEN CASE WHEN NEW.explicit_balance IS NULL THEN 1 ELSE 2 END ELSE observed_priority END,
      resolution_status = CASE WHEN NEW.member_id IS NULL THEN resolution_status ELSE 'verified' END,
      updated_at = CURRENT_TIMESTAMP
    WHERE faction_id = NEW.faction_id AND (
      (NEW.member_id IS NOT NULL AND member_id = NEW.member_id)
      OR (NEW.member_id IS NULL AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE)
    );

    SELECT CASE WHEN NEW.payout_request_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM payout_requests
      WHERE faction_id = NEW.faction_id
        AND id = NEW.payout_request_id
        AND member_id = NEW.member_id
        AND status IN ('pending', 'approved')
    ) THEN RAISE(ABORT, 'payout request settlement failed') END;

    UPDATE payout_requests SET
      status = 'paid',
      updated_at = CURRENT_TIMESTAMP
    WHERE NEW.kind = 'payout'
      AND NEW.payout_request_id IS NOT NULL
      AND faction_id = NEW.faction_id
      AND id = NEW.payout_request_id
      AND member_id = NEW.member_id
      AND status IN ('pending', 'approved');
  END`;

const applyMemberBalanceObservationTrigger = `CREATE TRIGGER IF NOT EXISTS apply_member_balance_observation
  AFTER INSERT ON member_balance_observations
  BEGIN
    SELECT CASE WHEN NEW.member_id IS NULL AND (
      SELECT COUNT(*) FROM member_balances
      WHERE faction_id = NEW.faction_id AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE
    ) > 1 THEN RAISE(ABORT, 'ambiguous member balance identity') END;

    UPDATE member_balances SET
      member_id = NEW.member_id,
      member_name = NEW.member_name,
      resolution_status = 'verified',
      updated_at = CURRENT_TIMESTAMP
    WHERE NEW.member_id IS NOT NULL
      AND id = (
        SELECT MIN(id) FROM member_balances
        WHERE faction_id = NEW.faction_id AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE
        HAVING COUNT(*) = 1
      )
      AND NOT EXISTS (
        SELECT 1 FROM member_balances WHERE faction_id = NEW.faction_id AND member_id = NEW.member_id
      );

    INSERT INTO member_balances
      (faction_id, member_id, member_name, balance, earned_total, paid_total, resolution_status)
    SELECT NEW.faction_id, NEW.member_id, NEW.member_name, 0, 0, 0, 'verified'
    WHERE NEW.member_id IS NOT NULL
    ON CONFLICT(faction_id, member_id) WHERE member_id IS NOT NULL DO UPDATE SET
      member_name = excluded.member_name,
      resolution_status = 'verified',
      updated_at = CURRENT_TIMESTAMP;

    INSERT INTO member_balances
      (faction_id, member_id, member_name, balance, earned_total, paid_total, resolution_status)
    SELECT NEW.faction_id, NULL, NEW.member_name, 0, 0, 0, 'unresolved'
    WHERE NEW.member_id IS NULL AND NOT EXISTS (
      SELECT 1 FROM member_balances
      WHERE faction_id = NEW.faction_id AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE
    );

    UPDATE member_balances SET
      member_name = NEW.member_name,
      balance = CASE WHEN
        observed_at IS NULL
        OR julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) > julianday(observed_at)
        OR (
          julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) = julianday(observed_at)
          AND 2 >= observed_priority
        )
      THEN NEW.new_balance ELSE balance END,
      observed_at = CASE WHEN
        observed_at IS NULL
        OR julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) > julianday(observed_at)
        OR (
          julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) = julianday(observed_at)
          AND 2 >= observed_priority
        )
      THEN COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP) ELSE observed_at END,
      observed_priority = CASE WHEN
        observed_at IS NULL
        OR julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) > julianday(observed_at)
        OR (
          julianday(COALESCE(NEW.occurred_at, CURRENT_TIMESTAMP)) = julianday(observed_at)
          AND 2 >= observed_priority
        )
      THEN 2 ELSE observed_priority END,
      resolution_status = CASE WHEN NEW.member_id IS NULL THEN resolution_status ELSE 'verified' END,
      updated_at = CURRENT_TIMESTAMP
    WHERE faction_id = NEW.faction_id AND (
      (NEW.member_id IS NOT NULL AND member_id = NEW.member_id)
      OR (NEW.member_id IS NULL AND member_id IS NULL AND member_name = NEW.member_name COLLATE NOCASE)
    );
  END`;

function normalizedObservedAt(value?: string | null) {
  const parsed = Date.parse(value ?? "");
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : new Date().toISOString();
}

export async function ensureMemberBalanceSchema(db: D1Database) {
  const existingEntries = await db.prepare(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'member_balance_entries'",
  ).first<{ name: string }>();
  if (existingEntries) {
    const existingColumns = await db.prepare("PRAGMA table_info(member_balance_entries)").all<{ name: string }>();
    const columnNames = new Set(existingColumns.results.map((column) => column.name));
    const missingColumns = ["explicit_balance", "payout_request_id"].filter((column) => !columnNames.has(column));
    if (missingColumns.length) {
      throw new Error(
        `Member balance schema migration required; member_balance_entries is missing: ${missingColumns.join(", ")}.`,
      );
    }
  }

  await ensureFactionFoundation(db);
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS member_balances (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      faction_id INTEGER NOT NULL,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
      earned_total INTEGER NOT NULL DEFAULT 0 CHECK (earned_total >= 0),
      paid_total INTEGER NOT NULL DEFAULT 0 CHECK (paid_total >= 0),
      observed_at TEXT,
      observed_priority INTEGER NOT NULL DEFAULT 0,
      resolution_status TEXT NOT NULL DEFAULT 'unresolved',
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE UNIQUE INDEX IF NOT EXISTS member_balances_faction_member_unique ON member_balances(faction_id, member_id) WHERE member_id IS NOT NULL"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_member_balances_faction_name ON member_balances(faction_id, member_name COLLATE NOCASE)"),
    db.prepare(`CREATE TABLE IF NOT EXISTS member_balance_entries (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      amount INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('credit', 'payout')),
      source TEXT NOT NULL CHECK (source IN ('war', 'oc', 'funds')),
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      explicit_balance INTEGER,
      payout_request_id INTEGER,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS member_balance_observations (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      old_balance INTEGER NOT NULL CHECK (old_balance >= 0),
      new_balance INTEGER NOT NULL CHECK (new_balance >= 0),
      delta INTEGER NOT NULL,
      direction TEXT NOT NULL CHECK (direction IN ('increase', 'decrease')),
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS payout_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      faction_id INTEGER NOT NULL,
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
    db.prepare("CREATE INDEX IF NOT EXISTS idx_member_entries_faction_created ON member_balance_entries(faction_id, created_at DESC)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_member_observations_faction_created ON member_balance_observations(faction_id, created_at DESC)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_payout_requests_faction_status ON payout_requests(faction_id, status, created_at DESC)"),
  ]);

  const entryColumns = await db.prepare("PRAGMA table_info(member_balance_entries)").all<{ name: string }>();
  const entryColumnNames = new Set(entryColumns.results.map((column) => column.name));
  const missingColumns = ["explicit_balance", "payout_request_id"].filter((column) => !entryColumnNames.has(column));
  if (missingColumns.length) {
    throw new Error(
      `Member balance schema migration required; member_balance_entries is missing: ${missingColumns.join(", ")}.`,
    );
  }
  await db.batch([
    db.prepare(applyMemberBalanceEntryTrigger),
    db.prepare(applyMemberBalanceObservationTrigger),
  ]);
}

function observationIsNewer(row: BalanceRow, observedAt: string, priority: number) {
  if (!row.observed_at) return true;
  const incoming = Date.parse(observedAt);
  const current = Date.parse(row.observed_at);
  return incoming > current || (incoming === current && priority >= row.observed_priority);
}

async function memberIdentity(db: D1Database, context: FactionContext, memberId: number | undefined, memberName: string) {
  const resolvedId = memberId ?? await resolveMemberIdByName(db, context, memberName) ?? undefined;
  if (resolvedId) {
    const canonical = await db.prepare("SELECT * FROM member_balances WHERE faction_id = ? AND member_id = ? LIMIT 1")
      .bind(context.factionId, resolvedId).first<BalanceRow>();
    if (canonical) return { memberId: resolvedId, row: canonical };
    const unresolved = await db.prepare(`SELECT * FROM member_balances
      WHERE faction_id = ? AND member_id IS NULL AND member_name = ? COLLATE NOCASE
      ORDER BY id ASC LIMIT 2`).bind(context.factionId, memberName).all<BalanceRow>();
    if (unresolved.results.length === 1) {
      await db.prepare(`UPDATE member_balances SET member_id = ?, member_name = ?, resolution_status = 'verified', updated_at = CURRENT_TIMESTAMP
        WHERE id = ? AND faction_id = ? AND member_id IS NULL`)
        .bind(resolvedId, memberName, unresolved.results[0].id, context.factionId).run();
      return { memberId: resolvedId, row: { ...unresolved.results[0], member_id: resolvedId, member_name: memberName } };
    }
    return { memberId: resolvedId, row: null };
  }
  const unresolved = await db.prepare(`SELECT * FROM member_balances
    WHERE faction_id = ? AND member_id IS NULL AND member_name = ? COLLATE NOCASE
    ORDER BY id ASC LIMIT 2`).bind(context.factionId, memberName).all<BalanceRow>();
  if (unresolved.results.length > 1) {
    throw new Error(`Ambiguous legacy balance rows for ${memberName}; manual resolution is required.`);
  }
  return { memberId: undefined, row: unresolved.results[0] ?? null };
}

async function writeBalance(
  db: D1Database,
  context: FactionContext,
  memberId: number | undefined,
  memberName: string,
  observedAt: string,
  priority: number,
  values: { explicitBalance?: number; inferredDelta?: number; earned?: number; paid?: number },
) {
  const identity = await memberIdentity(db, context, memberId, memberName);
  const row = identity.row;
  if (!row) {
    const startingBalance = values.explicitBalance ?? Math.max(0, values.inferredDelta ?? 0);
    await db.prepare(`INSERT INTO member_balances
      (faction_id, member_id, member_name, balance, earned_total, paid_total, observed_at, observed_priority, resolution_status)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`)
      .bind(context.factionId, identity.memberId ?? null, memberName, startingBalance, values.earned ?? 0, values.paid ?? 0,
        observedAt, priority, identity.memberId ? "verified" : "unresolved").run();
    return;
  }

  const newer = observationIsNewer(row, observedAt, priority);
  let balance = row.balance;
  if (newer && values.explicitBalance !== undefined) balance = Math.max(0, values.explicitBalance);
  else if (newer && values.inferredDelta !== undefined) balance = Math.max(0, balance + values.inferredDelta);
  await db.prepare(`UPDATE member_balances SET
      member_id = COALESCE(?, member_id), member_name = ?, balance = ?,
      earned_total = earned_total + ?, paid_total = paid_total + ?,
      observed_at = CASE WHEN ? THEN ? ELSE observed_at END,
      observed_priority = CASE WHEN ? THEN ? ELSE observed_priority END,
      resolution_status = CASE WHEN COALESCE(?, member_id) IS NULL THEN resolution_status ELSE 'verified' END,
      updated_at = CURRENT_TIMESTAMP
    WHERE id = ? AND faction_id = ?`)
    .bind(identity.memberId ?? null, memberName, balance, values.earned ?? 0, values.paid ?? 0,
      newer ? 1 : 0, observedAt, newer ? 1 : 0, priority, identity.memberId ?? null, row.id, context.factionId).run();
}

export async function recordExplicitBalance(
  db: D1Database,
  context: FactionContext,
  memberName: string,
  balance: number,
  observedAt: string,
  memberId?: number,
) {
  await writeBalance(db, context, memberId, memberName, normalizedObservedAt(observedAt), 2, { explicitBalance: balance });
}

export async function recordBalanceObservation(db: D1Database, context: FactionContext, event: BalanceObservation) {
  const oldBalance = Math.max(0, Math.trunc(event.oldBalance));
  const newBalance = Math.max(0, Math.trunc(event.newBalance));
  const delta = newBalance - oldBalance;
  const resolvedId = event.memberId ?? await resolveMemberIdByName(db, context, event.memberName) ?? undefined;
  const occurredAt = normalizedObservedAt(event.occurredAt);
  const inserted = await db.prepare(`INSERT OR IGNORE INTO member_balance_observations
    (faction_id, event_key, member_id, member_name, old_balance, new_balance, delta, direction, summary, occurred_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
    .bind(context.factionId, event.eventKey, resolvedId ?? null, event.memberName, oldBalance, newBalance, delta,
      event.direction, event.summary, occurredAt).run();
  return Boolean(inserted.meta.changes);
}

export async function recordBalanceEvent(db: D1Database, context: FactionContext, event: BalanceEvent) {
  const statement = await prepareBalanceEventInsert(db, context, event);
  const inserted = await statement.run();
  return Boolean(inserted.meta.changes);
}

export async function prepareBalanceEventInsert(db: D1Database, context: FactionContext, event: BalanceEvent) {
  const resolvedId = event.memberId ?? await resolveMemberIdByName(db, context, event.memberName) ?? undefined;
  const occurredAt = normalizedObservedAt(event.occurredAt);
  return db.prepare(`INSERT OR IGNORE INTO member_balance_entries
    (faction_id, event_key, member_id, member_name, amount, kind, source, summary, occurred_at, explicit_balance, payout_request_id)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CASE WHEN ? = 'payout' AND ? IS NOT NULL THEN (
      SELECT id FROM payout_requests
      WHERE faction_id = ? AND member_id = ? AND status IN ('pending', 'approved') AND amount <= ?
      ORDER BY created_at ASC, id ASC LIMIT 1
    ) ELSE NULL END)`)
    .bind(context.factionId, event.eventKey, resolvedId ?? null, event.memberName, event.amount, event.kind,
      event.source, event.summary, occurredAt, event.explicitBalance ?? null, event.kind, resolvedId ?? null,
      context.factionId, resolvedId ?? null, event.amount);
}
