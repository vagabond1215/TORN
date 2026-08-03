import { sql } from "drizzle-orm";
import { check, index, integer, primaryKey, sqliteTable, text } from "drizzle-orm/sqlite-core";

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

export const policies = sqliteTable("policies", {
  sourceKey: text("source_key").primaryKey(),
  label: text("label").notNull(),
  taxBps: integer("tax_bps").notNull().default(0),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [check("policies_tax_range", sql`${table.taxBps} BETWEEN 0 AND 10000`)]);

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

export const pendingWars = sqliteTable(
  "pending_wars",
  {
    warId: integer("war_id").primaryKey(),
    factionId: integer("faction_id").notNull(),
    opponentName: text("opponent_name").notNull(),
    startedAt: integer("started_at").notNull(),
    endedAt: integer("ended_at").notNull(),
    won: integer("won").notNull().default(0),
    grossEstimate: integer("gross_estimate").notNull().default(0),
    reviewedValue: integer("reviewed_value"),
    status: text("status").notNull().default("pending"),
    rewardsJson: text("rewards_json").notNull().default("[]"),
    membersJson: text("members_json").notNull().default("[]"),
    createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
    updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  },
  (table) => [
    check("pending_wars_status", sql`${table.status} IN ('pending', 'recorded', 'dismissed')`),
    index("idx_pending_wars_status_end").on(table.status, table.endedAt),
  ],
);

export const activeWar = sqliteTable("active_war", {
  warId: integer("war_id").primaryKey(),
  factionId: integer("faction_id").notNull(),
  opponentName: text("opponent_name").notNull(),
  startedAt: integer("started_at").notNull(),
  target: integer("target").notNull().default(0),
  ourScore: integer("our_score").notNull().default(0),
  theirScore: integer("their_score").notNull().default(0),
  ourChain: integer("our_chain").notNull().default(0),
  theirChain: integer("their_chain").notNull().default(0),
  membersJson: text("members_json").notNull().default("[]"),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});

export const warMemberBaselines = sqliteTable(
  "war_member_baselines",
  {
    warId: integer("war_id").notNull(),
    userId: integer("user_id").notNull(),
    name: text("name").notNull(),
    baseHits: integer("base_hits").notNull().default(0),
    baseXanax: integer("base_xanax").notNull().default(0),
    baseRefills: integer("base_refills").notNull().default(0),
    currentHits: integer("current_hits").notNull().default(0),
    currentXanax: integer("current_xanax").notNull().default(0),
    currentRefills: integer("current_refills").notNull().default(0),
    updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  },
  (table) => [primaryKey({ columns: [table.warId, table.userId] })],
);

export const tornBrowserEvents = sqliteTable(
  "torn_browser_events",
  {
    eventKey: text("event_key").primaryKey(),
    eventType: text("event_type").notNull(),
    category: text("category").notNull(),
    occurredAt: text("occurred_at"),
    summary: text("summary").notNull(),
    sourceUrl: text("source_url").notNull().default(""),
    payloadJson: text("payload_json").notNull().default("{}"),
    createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  },
  (table) => [index("idx_torn_browser_events_created").on(table.createdAt)],
);

export const treasuryLeaders = sqliteTable("treasury_leaders", {
  email: text("email").primaryKey(),
  displayName: text("display_name").notNull().default(""),
  addedBy: text("added_by").notNull().default(""),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});

export const memberBalances = sqliteTable("member_balances", {
  memberName: text("member_name").primaryKey(),
  memberId: integer("member_id"),
  balance: integer("balance").notNull().default(0),
  earnedTotal: integer("earned_total").notNull().default(0),
  paidTotal: integer("paid_total").notNull().default(0),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});

export const memberBalanceEntries = sqliteTable("member_balance_entries", {
  eventKey: text("event_key").primaryKey(),
  memberId: integer("member_id"),
  memberName: text("member_name").notNull(),
  amount: integer("amount").notNull(),
  kind: text("kind").notNull(),
  source: text("source").notNull(),
  summary: text("summary").notNull().default(""),
  occurredAt: text("occurred_at"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});

export const payoutRequests = sqliteTable("payout_requests", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  memberId: integer("member_id").notNull(),
  memberName: text("member_name").notNull(),
  amount: integer("amount").notNull(),
  status: text("status").notNull().default("pending"),
  deliveryPreference: text("delivery_preference").notNull().default("offline"),
  note: text("note").notNull().default(""),
  requestedByUserId: text("requested_by_user_id").notNull(),
  requestedByEmail: text("requested_by_email").notNull(),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
});

export const ocHoldings = sqliteTable("oc_holdings", {
  eventKey: text("event_key").primaryKey(),
  crimeName: text("crime_name").notNull(),
  status: text("status").notNull().default("held"),
  cashAmount: integer("cash_amount").notNull().default(0),
  itemsJson: text("items_json").notNull().default("[]"),
  summary: text("summary").notNull().default(""),
  occurredAt: text("occurred_at"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [index("idx_oc_holdings_status_created").on(table.status, table.createdAt)]);

export const armoryItems = sqliteTable("armory_items", {
  itemName: text("item_name").primaryKey(),
  category: text("category").notNull().default("other"),
  quantity: integer("quantity").notNull().default(0),
  source: text("source").notNull().default("activity"),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [index("idx_armory_items_category_name").on(table.category, table.itemName)]);
