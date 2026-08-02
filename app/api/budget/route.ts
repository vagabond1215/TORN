import { getD1 } from "../../../db";

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
  created_at: string;
};

const colors = ["lime", "amber", "blue", "violet", "rose", "cyan"];

async function ensureSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS accounts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      allocation_bps INTEGER NOT NULL DEFAULT 0 CHECK (allocation_bps BETWEEN 0 AND 10000),
      balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
      color TEXT NOT NULL DEFAULT 'lime',
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
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON transactions(created_at DESC, id DESC)"),
    db.prepare("PRAGMA optimize"),
  ]);

  const count = await db.prepare("SELECT COUNT(*) AS count FROM accounts").first<{ count: number }>();
  if (!count?.count) {
    await db.batch([
      db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, ?, ?)").bind("War Chest", 4000, "lime"),
      db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, ?, ?)").bind("Member Payouts", 3000, "amber"),
      db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, ?, ?)").bind("Armory", 2000, "blue"),
      db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, ?, ?)").bind("Emergency Reserve", 1000, "violet"),
    ]);
  }
}

function asPositiveInteger(value: unknown, label: string) {
  const amount = typeof value === "number" ? value : Number(value);
  if (!Number.isSafeInteger(amount) || amount <= 0) {
    throw new Error(`${label} must be a positive whole number.`);
  }
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

async function snapshot(db: D1Database) {
  const [accountsResult, transactionsResult] = await Promise.all([
    db.prepare("SELECT * FROM accounts ORDER BY id ASC").all<AccountRow>(),
    db.prepare("SELECT * FROM transactions ORDER BY created_at DESC, id DESC LIMIT 150").all<TransactionRow>(),
  ]);

  return {
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
      createdAt: transaction.created_at,
    })),
  };
}

export async function GET() {
  try {
    const db = getD1();
    await ensureSchema(db);
    return Response.json(await snapshot(db));
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unable to load the budget." }, { status: 500 });
  }
}

export async function POST(request: Request) {
  try {
    const payload = (await request.json()) as Record<string, unknown>;
    const action = String(payload.action ?? "");
    const db = getD1();
    await ensureSchema(db);

    if (action === "deposit") {
      const amount = asPositiveInteger(payload.amount, "Proceeds");
      const note = String(payload.note ?? "War proceeds").trim().slice(0, 160) || "War proceeds";
      const result = await db.prepare("SELECT * FROM accounts ORDER BY id ASC").all<AccountRow>();
      const accounts = result.results;
      const totalBps = accounts.reduce((sum, account) => sum + account.allocation_bps, 0);
      if (totalBps !== 10000) throw new Error("Allocations must total 100% before recording proceeds.");

      const allocations = accounts.map((account) => {
        const exact = amount * account.allocation_bps;
        return { account, amount: Math.floor(exact / 10000), remainder: exact % 10000 };
      });
      let remainder = amount - allocations.reduce((sum, item) => sum + item.amount, 0);
      for (const item of [...allocations].sort((a, b) => b.remainder - a.remainder || a.account.id - b.account.id)) {
        if (remainder <= 0) break;
        item.amount += 1;
        remainder -= 1;
      }

      const statements = allocations
        .filter((item) => item.amount > 0)
        .map((item) => db.prepare("UPDATE accounts SET balance = balance + ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(item.amount, item.account.id));
      statements.push(
        db.prepare("INSERT INTO transactions (type, amount, note, details) VALUES ('deposit', ?, ?, ?)").bind(
          amount,
          note,
          JSON.stringify({ allocations: allocations.map((item) => ({ accountId: item.account.id, name: item.account.name, amount: item.amount, allocationBps: item.account.allocation_bps })) }),
        ),
      );
      await db.batch(statements);
    } else if (action === "spend") {
      const amount = asPositiveInteger(payload.amount, "Spend amount");
      const account = await accountById(db, asAccountId(payload.accountId));
      if (account.balance < amount) throw new Error(`${account.name} does not have enough funds.`);
      const note = String(payload.note ?? "").trim().slice(0, 160);
      if (!note) throw new Error("Add a note describing the expense.");
      await db.batch([
        db.prepare("UPDATE accounts SET balance = balance - ?, updated_at = CURRENT_TIMESTAMP WHERE id = ?").bind(amount, account.id),
        db.prepare("INSERT INTO transactions (type, amount, from_account_id, from_account_name, note) VALUES ('spend', ?, ?, ?, ?)").bind(amount, account.id, account.name, note),
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
        db.prepare("INSERT INTO transactions (type, amount, from_account_id, from_account_name, to_account_id, to_account_name, note) VALUES ('transfer', ?, ?, ?, ?, ?, ?)").bind(amount, from.id, from.name, to.id, to.name, note),
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
      statements.push(db.prepare("INSERT INTO transactions (type, note, details) VALUES ('allocation_update', 'Allocation plan updated', ?)").bind(JSON.stringify({ accounts: updates })));
      await db.batch(statements);
    } else if (action === "addAccount") {
      const name = String(payload.name ?? "").trim().slice(0, 50);
      if (!name) throw new Error("Enter an account name.");
      const count = await db.prepare("SELECT COUNT(*) AS count FROM accounts").first<{ count: number }>();
      const color = colors[(count?.count ?? 0) % colors.length];
      await db.batch([
        db.prepare("INSERT INTO accounts (name, allocation_bps, color) VALUES (?, 0, ?)").bind(name, color),
        db.prepare("INSERT INTO transactions (type, note, details) VALUES ('account_created', ?, ?)").bind(`${name} created`, JSON.stringify({ name })),
      ]);
    } else if (action === "deleteAccount") {
      const account = await accountById(db, asAccountId(payload.accountId));
      if (account.balance !== 0) throw new Error("Transfer or spend this account's balance before deleting it.");
      const count = await db.prepare("SELECT COUNT(*) AS count FROM accounts").first<{ count: number }>();
      if ((count?.count ?? 0) <= 1) throw new Error("Keep at least one account.");
      await db.batch([
        db.prepare("DELETE FROM accounts WHERE id = ?").bind(account.id),
        db.prepare("INSERT INTO transactions (type, note, details) VALUES ('account_deleted', ?, ?)").bind(`${account.name} deleted`, JSON.stringify({ name: account.name })),
      ]);
    } else {
      return Response.json({ error: "Unknown action." }, { status: 400 });
    }

    return Response.json(await snapshot(db));
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to update the budget.";
    return Response.json({ error: message }, { status: /must|required|choose|enough|not found|keep|before/i.test(message) ? 400 : 500 });
  }
}
