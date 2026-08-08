import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema, recordBalanceEvent } from "../../../db/member-balances";
import { requireTreasuryLeader, TreasuryAccessError } from "../../treasury-access";

type AccountRow = {
  id: number;
  name: string;
  allocation_bps: number;
  balance: number;
  color: string;
  created_at: string;
  updated_at: string;
};

type TransactionRow = {
  id: number;
  type: string;
  amount: number;
  from_account_id: number | null;
  from_account_name: string | null;
  to_account_id: number | null;
  to_account_name: string | null;
  note: string;
  details: string;
  actor_user_id: string | null;
  actor_email: string | null;
  actor_name: string | null;
  created_at: string;
};

type PolicyRow = {
  source_key: string;
  label: string;
  tax_bps: number;
  created_at: string;
  updated_at: string;
};

type Actor = { userId: string; email: string; name: string };

const colors = ["crimson", "gold", "silver", "wine", "ember", "bone"];
const defaultAccounts = [
  { name: "War Supply Reserve", allocationBps: 4500, color: "crimson" },
  { name: "Strategic Reserve", allocationBps: 3000, color: "gold" },
  { name: "Chain Extensions", allocationBps: 1500, color: "silver" },
  { name: "Faction Operations", allocationBps: 1000, color: "wine" },
];
const defaultPolicies = [
  { sourceKey: "war", label: "Ranked war", taxBps: 2000 },
  { sourceKey: "oc", label: "Organized crime", taxBps: 500 },
  { sourceKey: "other", label: "Other faction income", taxBps: 10000 },
];

function actorValues(actor: Actor) {
  return [actor.userId, actor.email, actor.name] as const;
}

async function ensureSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      allocation_bps INTEGER NOT NULL DEFAULT 0 CHECK (allocation_bps BETWEEN 0 AND 10000),
      balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
      color TEXT NOT NULL DEFAULT 'crimson',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      amount INTEGER NOT NULL DEFAULT 0,
      from_account_id INTEGER,
      from_account_name TEXT,
      to_account_id INTEGER,
      to_account_name TEXT,
      note TEXT NOT NULL DEFAULT '',
      details TEXT NOT NULL DEFAULT '{}',
      actor_user_id TEXT,
      actor_email TEXT,
      actor_name TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS policies (
      source_key TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      tax_bps INTEGER NOT NULL DEFAULT 0 CHECK (tax_bps BETWEEN 0 AND 10000),
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS pending_wars (
      war_id INTEGER PRIMARY KEY,
      faction_id INTEGER NOT NULL,
      opponent_name TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER NOT NULL,
      won INTEGER NOT NULL DEFAULT 0,
      gross_estimate INTEGER NOT NULL DEFAULT 0,
      reviewed_value INTEGER,
      reviewed_tax_bps INTEGER NOT NULL DEFAULT 2000 CHECK (reviewed_tax_bps BETWEEN 0 AND 10000),
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'recorded', 'dismissed')),
      rewards_json TEXT NOT NULL DEFAULT '[]',
      members_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC, id DESC)"),
  ]);

  const columns = await db.prepare("PRAGMA table_info(transactions)").all<{ name: string }>();
  const columnNames = new Set(columns.results.map((column) => column.name));
  for (const column of ["actor_user_id", "actor_email", "actor_name"]) {
    if (!columnNames.has(column)) await db.prepare(`ALTER TABLE transactions ADD COLUMN ${column} TEXT`).run();
  }

  const count = await db.prepare("SELECT COUNT(*) AS count FROM accounts").first<{ count: number }>();
  if (!count?.count) {
    await db.batch(defaultAccounts.map((account) =>
      db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, ?, ?)")
        .bind(account.name, account.allocationBps, account.color),
    ));
  } else {
    await upgradeUntouchedDefaults(db);
  }

  await db.batch(defaultPolicies.map((policy) =>
    db.prepare("INSERT OR IGNORE INTO policies (source_key, label, tax_bps) VALUES (?, ?, ?)")
      .bind(policy.sourceKey, policy.label, policy.taxBps),
  ));

  await db.prepare("PRAGMA optimize").run();
}

async function upgradeUntouchedDefaults(db: D1Database) {
  const accounts = (await db.prepare("SELECT * FROM accounts ORDER BY id ASC").all<AccountRow>()).results;
  const financialEntries = await db.prepare("SELECT COUNT(*) AS count FROM transactions WHERE type IN ('deposit', 'spend', 'transfer')").first<{ count: number }>();
  const legacyNames = ["War Chest", "Member Payouts", "Armory", "Emergency Reserve"];
  const untouched = accounts.length === 4 && accounts.every((account, index) => account.balance === 0 && account.name === legacyNames[index]) && !financialEntries?.count;
  if (!untouched) return;

  const statements = accounts.map((account, index) => {
    const replacement = defaultAccounts[index];
    return db.prepare("UPDATE accounts SET name = ?, allocation_bps = ?, color = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?")
      .bind(replacement.name, replacement.allocationBps, replacement.color, account.id);
  });
  statements.push(db.prepare(`INSERT INTO transactions (type, note, details, actor_user_id, actor_email, actor_name)
    VALUES ('policy_bootstrap', 'Blood Coven policy defaults applied', ?, 'system', 'system@blood-coven', 'Blood Coven setup')`)
    .bind(JSON.stringify({ accounts: defaultAccounts, warTaxPercent: 20, ocTaxPercent: 5, reserveFloor: 1_000_000_000, reserveTarget: 1_500_000_000 })));
  await db.batch(statements);
}

function asPositiveInteger(value: unknown, label: string) {
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(amount) || amount <= 0) throw new Error(`${label} must be a positive whole number.`);
  return amount;
}

function asAccountId(value: unknown) {
  return asPositiveInteger(value, "Account");
}

async function accountById(db: D1Database, id: number) {
  const account = await db.prepare("SELECT * FROM accounts WHERE id = ?").bind(id).first<AccountRow>();
  if (!account) throw new Error("Account not found.");
  return account;
}

async function snapshot(db: D1Database, actor: Actor) {
  const [accountsResult, policiesResult, transactionsResult] = await Promise.all([
    db.prepare("SELECT * FROM accounts ORDER BY id ASC").all<AccountRow>(),
    db.prepare("SELECT * FROM policies ORDER BY CASE source_key WHEN 'war' THEN 1 WHEN 'oc' THEN 2 ELSE 3 END").all<PolicyRow>(),
    db.prepare("SELECT * FROM transactions ORDER BY created_at DESC, id DESC LIMIT 150").all<TransactionRow>(),
  ]);

  return {
    currentUser: actor,
    policies: policiesResult.results.map((policy) => ({
      sourceKey: policy.source_key,
      label: policy.label,
      taxBps: policy.tax_bps,
      updatedAt: policy.updated_at,
    })),
    accounts: accountsResult.results.map((account) => ({
      id: account.id,
      name: account.name,
      allocationBps: account.allocation_bps,
      balance: account.balance,
      color: account.color,
      createdAt: account.created_at,
      updatedAt: account.updated_at,
    })),
    transactions: transactionsResult.results.map((transaction) => ({
      id: transaction.id,
      type: transaction.type,
      amount: transaction.amount,
      fromAccountId: transaction.from_account_id,
      fromAccountName: transaction.from_account_name,
      toAccountId: transaction.to_account_id,
      toAccountName: transaction.to_account_name,
      note: transaction.note,
      details: JSON.parse(transaction.details || "{}"),
      actorUserId: transaction.actor_user_id,
      actorEmail: transaction.actor_email,
      actorName: transaction.actor_name,
      createdAt: transaction.created_at,
    })),
  };
}

export async function GET() {
  try {
    const db = getD1();
    await ensureSchema(db);
    const actor = await requireTreasuryLeader(db);
    return Response.json(await snapshot(db, actor));
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unable to load the budget." }, { status: error instanceof TreasuryAccessError ? 403 : 500 });
  }
}

export async function POST(request: Request) {
  try {
    const payload = (await request.json()) as Record<string, unknown>;
    const action = String(payload.action ?? "");
    const db = getD1();
    await ensureSchema(db);
    const actor = await requireTreasuryLeader(db);
    const actorParams = actorValues(actor);

    if (action === "deposit") {
      const grossAmount = asPositiveInteger(payload.amount, "Gross proceeds");
      const pendingWarId = payload.pendingWarId ? asPositiveInteger(payload.pendingWarId, "War") : null;
      const pendingWar = pendingWarId
        ? await db.prepare("SELECT war_id, opponent_name, members_json, reviewed_tax_bps FROM pending_wars WHERE war_id = ? AND status = 'pending'").bind(pendingWarId).first<{ war_id: number; opponent_name: string; members_json: string; reviewed_tax_bps: number }>()
        : null;
      if (pendingWarId && !pendingWar) throw new Error("This war review is no longer pending.");
      const sourceKey = pendingWar ? "war" : String(payload.sourceKey ?? "war").trim().slice(0, 30);
      const policy = await db.prepare("SELECT * FROM policies WHERE source_key = ?").bind(sourceKey).first<PolicyRow>();
      if (!policy) throw new Error("Choose a valid proceeds source.");
      const requestedTaxBps = pendingWar ? Number(payload.taxBpsOverride ?? pendingWar.reviewed_tax_bps) : policy.tax_bps;
      if (!Number.isInteger(requestedTaxBps) || requestedTaxBps < 0 || requestedTaxBps > 10000) throw new Error("Tax rate must be between 0% and 100%.");
      const taxBps = requestedTaxBps;
      const factionShare = Math.floor(grossAmount * taxBps / 10000);
      const playerPayout = grossAmount - factionShare;
      if (factionShare <= 0 && !pendingWar) throw new Error("This policy does not allocate any proceeds to the faction.");
      const note = String(payload.note ?? (pendingWar ? `Ranked war vs ${pendingWar.opponent_name}` : `${policy.label} proceeds`)).trim().slice(0, 160) || `${policy.label} proceeds`;
      const accounts = (await db.prepare("SELECT * FROM accounts ORDER BY id ASC").all<AccountRow>()).results;
      const totalBps = accounts.reduce((sum, account) => sum + account.allocation_bps, 0);
      if (totalBps !== 10000) throw new Error("Allocations must total 100% before recording proceeds.");

      const allocations = accounts.map((account) => {
        const exact = factionShare * account.allocation_bps;
        return { account, amount: Math.floor(exact / 10000), remainder: exact % 10000 };
      });
      let remainder = factionShare - allocations.reduce((sum, item) => sum + item.amount, 0);
      for (const item of [...allocations].sort((a, b) => b.remainder - a.remainder || a.account.id - b.account.id)) {
        if (remainder-- <= 0) break;
        item.amount += 1;
      }

      const statements = allocations.filter((item) => item.amount > 0)
        .map((item) => db.prepare("UPDATE accounts SET balance = balance + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(item.amount, item.account.id));
      statements.push(db.prepare(`INSERT INTO transactions (type, amount, note, details, actor_user_id, actor_email, actor_name)
        VALUES ('deposit', ?, ?, ?, ?, ?, ?)`)
        .bind(factionShare, note, JSON.stringify({ sourceKey, source: policy.label, grossAmount, taxBps, playerPayout, factionShare, pendingWarId, allocations: allocations.map((item) => ({ accountId: item.account.id, name: item.account.name, amount: item.amount, allocationBps: item.account.allocation_bps })) }), ...actorParams));
      if (pendingWarId) statements.push(db.prepare("UPDATE pending_wars SET status = 'recorded', reviewed_value = ?, reviewed_tax_bps = ?, updated_at = CURRENT_TIMESTAMP WHERE war_id = ? AND status = 'pending'").bind(grossAmount, taxBps, pendingWarId));
      await db.batch(statements);
      if (pendingWar) {
        await ensureMemberBalanceSchema(db);
        let members: Array<{ id: number; name: string; attacks: number }> = [];
        try { members = JSON.parse(pendingWar.members_json) as typeof members; } catch { members = []; }
        const eligible = members.filter((member) => member.id > 0 && member.name && member.attacks > 0);
        const totalAttacks = eligible.reduce((sum, member) => sum + member.attacks, 0);
        const payouts = eligible.map((member) => {
          const exact = playerPayout * member.attacks;
          return { member, amount: Math.floor(exact / totalAttacks), remainder: exact % totalAttacks };
        });
        let payoutRemainder = playerPayout - payouts.reduce((sum, item) => sum + item.amount, 0);
        for (const item of [...payouts].sort((a, b) => b.remainder - a.remainder || a.member.id - b.member.id)) {
          if (payoutRemainder-- <= 0) break;
          item.amount += 1;
        }
        for (const item of payouts.filter((entry) => entry.amount > 0)) {
          await recordBalanceEvent(db, {
            eventKey: `war:${pendingWar.war_id}:${item.member.id}`,
            memberId: item.member.id,
            memberName: item.member.name,
            amount: item.amount,
            kind: "credit",
            source: "war",
            summary: `Ranked war vs ${pendingWar.opponent_name}`,
          });
        }
      }
    } else if (action === "directDeposit") {
      const amount = asPositiveInteger(payload.amount, "Deposit amount");
      const account = await accountById(db, asAccountId(payload.accountId));
      const note = String(payload.note ?? "Direct account deposit").trim().slice(0, 160) || "Direct account deposit";
      await db.batch([
        db.prepare("UPDATE accounts SET balance = balance + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(amount, account.id),
        db.prepare(`INSERT INTO transactions (type, amount, to_account_id, to_account_name, note, actor_user_id, actor_email, actor_name)
          VALUES ('direct_deposit', ?, ?, ?, ?, ?, ?, ?)`)
          .bind(amount, account.id, account.name, note, ...actorParams),
      ]);
    } else if (action === "spend") {
      const amount = asPositiveInteger(payload.amount, "Spend amount");
      const account = await accountById(db, asAccountId(payload.accountId));
      if (account.balance < amount) throw new Error(`${account.name} does not have enough funds.`);
      const note = String(payload.note ?? "").trim().slice(0, 160);
      if (!note) throw new Error("Add a note describing the expense.");
      await db.batch([
        db.prepare("UPDATE accounts SET balance = balance - ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(amount, account.id),
        db.prepare(`INSERT INTO transactions (type, amount, from_account_id, from_account_name, note, actor_user_id, actor_email, actor_name)
          VALUES ('spend', ?, ?, ?, ?, ?, ?, ?)`)
          .bind(amount, account.id, account.name, note, ...actorParams),
      ]);
    } else if (action === "transfer") {
      const amount = asPositiveInteger(payload.amount, "Transfer amount");
      const from = await accountById(db, asAccountId(payload.fromAccountId));
      const to = await accountById(db, asAccountId(payload.toAccountId));
      if (from.id === to.id) throw new Error("Choose two different accounts.");
      if (from.balance < amount) throw new Error(`${from.name} does not have enough funds.`);
      const note = String(payload.note ?? "Account transfer").trim().slice(0, 160) || "Account transfer";
      await db.batch([
        db.prepare("UPDATE accounts SET balance = balance - ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(amount, from.id),
        db.prepare("UPDATE accounts SET balance = balance + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(amount, to.id),
        db.prepare(`INSERT INTO transactions (type, amount, from_account_id, from_account_name, to_account_id, to_account_name, note, actor_user_id, actor_email, actor_name)
          VALUES ('transfer', ?, ?, ?, ?, ?, ?, ?, ?, ?)`)
          .bind(amount, from.id, from.name, to.id, to.name, note, ...actorParams),
      ]);
    } else if (action === "setAllocations") {
      if (!Array.isArray(payload.accounts) || payload.accounts.length < 1) throw new Error("At least one account is required.");
      const updates = payload.accounts.map((value) => {
        const item = value as Record<string, unknown>;
        const id = asAccountId(item.id);
        const name = String(item.name ?? "").trim().slice(0, 50);
        const allocationBps = Number(item.allocationBps);
        if (!name) throw new Error("Every account needs a name.");
        if (!Number.isInteger(allocationBps) || allocationBps < 0 || allocationBps > 10000) throw new Error("Allocation percentages are invalid.");
        return { id, name, allocationBps };
      });
      if (updates.reduce((sum, item) => sum + item.allocationBps, 0) !== 10000) throw new Error("Allocations must total exactly 100%.");
      const statements = updates.map((item) => db.prepare("UPDATE accounts SET name = ?, allocation_bps = ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(item.name, item.allocationBps, item.id));
      statements.push(db.prepare(`INSERT INTO transactions (type, note, details, actor_user_id, actor_email, actor_name)
        VALUES ('allocation_update', 'Allocation plan updated', ?, ?, ?, ?)`)
        .bind(JSON.stringify({ accounts: updates }), ...actorParams));
      await db.batch(statements);
    } else if (action === "setPolicies") {
      if (!Array.isArray(payload.policies)) throw new Error("Policy values are required.");
      const updates = payload.policies.map((value) => {
        const item = value as Record<string, unknown>;
        const sourceKey = String(item.sourceKey ?? "");
        const taxBps = Number(item.taxBps);
        if (!defaultPolicies.some((policy) => policy.sourceKey === sourceKey)) throw new Error("Choose a valid policy.");
        if (!Number.isInteger(taxBps) || taxBps < 0 || taxBps > 10000) throw new Error("Tax percentages must be between 0% and 100%.");
        return { sourceKey, taxBps };
      });
      const statements = updates.map((item) => db.prepare("UPDATE policies SET tax_bps = ?, updated_at = CURRENT_TIMESTAMP WHERE source_key = ?").bind(item.taxBps, item.sourceKey));
      statements.push(db.prepare(`INSERT INTO transactions (type, note, details, actor_user_id, actor_email, actor_name)
        VALUES ('policy_update', 'Proceeds policies updated', ?, ?, ?, ?)`)
        .bind(JSON.stringify({ policies: updates }), ...actorParams));
      await db.batch(statements);
    } else if (action === "addAccount") {
      const name = String(payload.name ?? "").trim().slice(0, 50);
      if (!name) throw new Error("Enter an account name.");
      const count = await db.prepare("SELECT COUNT(*) AS count FROM accounts").first<{ count: number }>();
      const color = colors[(count?.count ?? 0) % colors.length];
      await db.batch([
        db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, 0, ?)").bind(name, color),
        db.prepare(`INSERT INTO transactions (type, note, details, actor_user_id, actor_email, actor_name)
          VALUES ('account_created', ?, ?, ?, ?, ?)`)
          .bind(`${name} created`, JSON.stringify({ name }), ...actorParams),
      ]);
    } else if (action === "deleteAccount") {
      const account = await accountById(db, asAccountId(payload.accountId));
      if (account.balance !== 0) throw new Error("Transfer or spend this account's balance before deleting it.");
      const count = await db.prepare("SELECT COUNT(*) AS count FROM accounts").first<{ count: number }>();
      if ((count?.count ?? 0) <= 1) throw new Error("Keep at least one account.");
      await db.batch([
        db.prepare("DELETE FROM accounts WHERE id = ?").bind(account.id),
        db.prepare(`INSERT INTO transactions (type, note, details, actor_user_id, actor_email, actor_name)
          VALUES ('account_deleted', ?, ?, ?, ?, ?)`)
          .bind(`${account.name} deleted`, JSON.stringify({ name: account.name }), ...actorParams),
      ]);
    } else {
      return Response.json({ error: "Unknown action." }, { status: 400 });
    }

    return Response.json(await snapshot(db, actor));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update the budget.";
    return Response.json({ error: message }, { status: error instanceof TreasuryAccessError ? 403 : /must|required|choose|enough|not found|keep|before|enter/i.test(message) ? 400 : 500 });
  }
}
