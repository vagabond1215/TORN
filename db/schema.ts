import { sql } from "drizzle-orm";
import { check, index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const accounts = sqliteTable(
  "accounts",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    name: text("name").notNull(),
    allocationBps: integer("allocation_bps").notNull().default(0),
    balance: integer("balance").notNull().default(0),
    color: text("color").notNull().default("lime"),
    createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
    updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  },
  (table) => [
    check("accounts_allocation_range", sql`${table.allocationBps} BETWEEN 0 AND 10000`),
    check("accounts_balance_nonnegative", sql`${table.balance} >= 0`),
  ],
);

export const transactions = sqliteTable(
  "transactions",
  {
    id: integer("id").primaryKey({ autoIncrement: true }),
    type: text("type").notNull(),
    amount: integer("amount").notNull().default(0),
    fromAccountId: integer("from_account_id"),
    fromAccountName: text("from_account_name"),
    toAccountId: integer("to_account_id"),
    toAccountName: text("to_account_name"),
    note: text("note").notNull().default(""),
    details: text("details").notNull().default("{}"),
    actorUserId: text("actor_user_id"),
    actorEmail: text("actor_email"),
    actorName: text("actor_name"),
    createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  },
  (table) => [index("idx_transactions_created_at").on(table.createdAt, table.id)],
);
