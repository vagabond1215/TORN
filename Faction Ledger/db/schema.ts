import { sql } from "drizzle-orm";
import { check, index, integer, primaryKey, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

export const factions = sqliteTable("factions", {
  factionId: integer("faction_id").primaryKey(),
  name: text("name").notNull(),
  slug: text("slug").notNull(),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [uniqueIndex("factions_slug_unique").on(table.slug)]);

export const factionMembers = sqliteTable("faction_members", {
  factionId: integer("faction_id").notNull(),
  memberId: integer("member_id").notNull(),
  memberName: text("member_name").notNull(),
  lastVerifiedAt: text("last_verified_at").notNull(),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.memberId] }),
  index("idx_faction_members_name").on(table.factionId, table.memberName),
]);

export const accounts = sqliteTable("accounts", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  factionId: integer("faction_id").notNull(),
  name: text("name").notNull(),
  allocationBps: integer("allocation_bps").notNull().default(0),
  balance: integer("balance").notNull().default(0),
  color: text("color").notNull().default("lime"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  check("accounts_allocation_range", sql`${table.allocationBps} BETWEEN 0 AND 10000`),
  check("accounts_balance_nonnegative", sql`${table.balance} >= 0`),
  uniqueIndex("accounts_faction_name_unique").on(table.factionId, table.name),
  index("idx_accounts_faction").on(table.factionId, table.id),
]);

export const policies = sqliteTable("policies", {
  factionId: integer("faction_id").notNull(),
  sourceKey: text("source_key").notNull(),
  label: text("label").notNull(),
  taxBps: integer("tax_bps").notNull().default(0),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.sourceKey] }),
  check("policies_tax_range", sql`${table.taxBps} BETWEEN 0 AND 10000`),
]);

export const transactions = sqliteTable("transactions", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  factionId: integer("faction_id").notNull(),
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
}, (table) => [index("idx_transactions_faction_created_at").on(table.factionId, table.createdAt, table.id)]);

export const pendingWars = sqliteTable("pending_wars", {
  factionId: integer("faction_id").notNull(),
  warId: integer("war_id").notNull(),
  opponentName: text("opponent_name").notNull(),
  startedAt: integer("started_at").notNull(),
  endedAt: integer("ended_at").notNull(),
  won: integer("won").notNull().default(0),
  grossEstimate: integer("gross_estimate").notNull().default(0),
  reviewedValue: integer("reviewed_value"),
  reviewedTaxBps: integer("reviewed_tax_bps").notNull().default(2000),
  status: text("status").notNull().default("pending"),
  rewardsJson: text("rewards_json").notNull().default("[]"),
  membersJson: text("members_json").notNull().default("[]"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.warId] }),
  check("pending_wars_status", sql`${table.status} IN ('pending', 'recorded', 'dismissed')`),
  check("pending_wars_tax_range", sql`${table.reviewedTaxBps} BETWEEN 0 AND 10000`),
  index("idx_pending_wars_faction_status_end").on(table.factionId, table.status, table.endedAt),
]);

export const activeWar = sqliteTable("active_war", {
  factionId: integer("faction_id").notNull(),
  warId: integer("war_id").notNull(),
  opponentName: text("opponent_name").notNull(),
  startedAt: integer("started_at").notNull(),
  target: integer("target").notNull().default(0),
  ourScore: integer("our_score").notNull().default(0),
  theirScore: integer("their_score").notNull().default(0),
  ourChain: integer("our_chain").notNull().default(0),
  theirChain: integer("their_chain").notNull().default(0),
  membersJson: text("members_json").notNull().default("[]"),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.warId] })]);

export const warMemberBaselines = sqliteTable("war_member_baselines", {
  factionId: integer("faction_id").notNull(),
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
}, (table) => [primaryKey({ columns: [table.factionId, table.warId, table.userId] })]);

export const tornBrowserEvents = sqliteTable("torn_browser_events", {
  factionId: integer("faction_id").notNull(),
  eventKey: text("event_key").notNull(),
  eventType: text("event_type").notNull(),
  category: text("category").notNull(),
  occurredAt: text("occurred_at"),
  summary: text("summary").notNull(),
  sourceUrl: text("source_url").notNull().default(""),
  payloadJson: text("payload_json").notNull().default("{}"),
  firstObservedAt: text("first_observed_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  lastObservedAt: text("last_observed_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.eventKey] }),
  index("idx_torn_browser_events_faction_created").on(table.factionId, table.createdAt),
]);

export const treasuryLeaders = sqliteTable("treasury_leaders", {
  factionId: integer("faction_id").notNull(),
  email: text("email").notNull(),
  displayName: text("display_name").notNull().default(""),
  addedBy: text("added_by").notNull().default(""),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.email] })]);

export const memberBalances = sqliteTable("member_balances", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  factionId: integer("faction_id").notNull(),
  memberId: integer("member_id"),
  memberName: text("member_name").notNull(),
  balance: integer("balance").notNull().default(0),
  earnedTotal: integer("earned_total").notNull().default(0),
  paidTotal: integer("paid_total").notNull().default(0),
  observedAt: text("observed_at"),
  observedPriority: integer("observed_priority").notNull().default(0),
  resolutionStatus: text("resolution_status").notNull().default("unresolved"),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  uniqueIndex("member_balances_faction_member_unique").on(table.factionId, table.memberId).where(sql`${table.memberId} IS NOT NULL`),
  index("idx_member_balances_faction_name").on(table.factionId, table.memberName),
  check("member_balances_nonnegative", sql`${table.balance} >= 0 AND ${table.earnedTotal} >= 0 AND ${table.paidTotal} >= 0`),
]);

export const memberBalanceEntries = sqliteTable("member_balance_entries", {
  factionId: integer("faction_id").notNull(),
  eventKey: text("event_key").notNull(),
  memberId: integer("member_id"),
  memberName: text("member_name").notNull(),
  amount: integer("amount").notNull(),
  kind: text("kind").notNull(),
  source: text("source").notNull(),
  summary: text("summary").notNull().default(""),
  occurredAt: text("occurred_at"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.eventKey] }),
  index("idx_member_entries_faction_created").on(table.factionId, table.createdAt),
]);

export const memberBalanceObservations = sqliteTable("member_balance_observations", {
  factionId: integer("faction_id").notNull(),
  eventKey: text("event_key").notNull(),
  memberId: integer("member_id"),
  memberName: text("member_name").notNull(),
  oldBalance: integer("old_balance").notNull(),
  newBalance: integer("new_balance").notNull(),
  delta: integer("delta").notNull(),
  direction: text("direction").notNull(),
  summary: text("summary").notNull().default(""),
  occurredAt: text("occurred_at"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.eventKey] }),
  index("idx_member_observations_faction_created").on(table.factionId, table.createdAt),
]);

export const payoutRequests = sqliteTable("payout_requests", {
  id: integer("id").primaryKey({ autoIncrement: true }),
  factionId: integer("faction_id").notNull(),
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
}, (table) => [
  index("idx_payout_requests_faction_status").on(table.factionId, table.status, table.createdAt),
  index("idx_payout_requests_faction_member").on(table.factionId, table.memberId),
]);

export const ocHoldings = sqliteTable("oc_holdings", {
  factionId: integer("faction_id").notNull(),
  eventKey: text("event_key").notNull(),
  crimeName: text("crime_name").notNull(),
  status: text("status").notNull().default("held"),
  cashAmount: integer("cash_amount").notNull().default(0),
  itemsJson: text("items_json").notNull().default("[]"),
  summary: text("summary").notNull().default(""),
  occurredAt: text("occurred_at"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.eventKey] }),
  index("idx_oc_holdings_faction_status_created").on(table.factionId, table.status, table.createdAt),
]);

export const armoryItems = sqliteTable("armory_items", {
  factionId: integer("faction_id").notNull(),
  itemName: text("item_name").notNull(),
  category: text("category").notNull().default("other"),
  quantity: integer("quantity").notNull().default(0),
  source: text("source").notNull().default("activity"),
  observedAt: text("observed_at"),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [
  primaryKey({ columns: [table.factionId, table.itemName] }),
  index("idx_armory_items_faction_category_name").on(table.factionId, table.category, table.itemName),
]);

export const armorySnapshotState = sqliteTable("armory_snapshot_state", {
  factionId: integer("faction_id").notNull(),
  category: text("category").notNull(),
  eventKey: text("event_key").notNull(),
  observedAt: text("observed_at").notNull(),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.category] })]);

export const armoryItemEffects = sqliteTable("armory_item_effects", {
  factionId: integer("faction_id").notNull(),
  eventKey: text("event_key").notNull(),
  itemName: text("item_name").notNull(),
  delta: integer("delta").notNull().default(0),
  category: text("category").notNull().default("other"),
  source: text("source").notNull().default("activity"),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.eventKey, table.itemName] })]);

export const tornSyncCursors = sqliteTable("torn_sync_cursors", {
  factionId: integer("faction_id").notNull(),
  sourceKey: text("source_key").notNull(),
  nextOffset: integer("next_offset").notNull().default(0),
  complete: integer("complete").notNull().default(0),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.sourceKey] })]);

export const scriptSyncTokens = sqliteTable("script_sync_tokens", {
  tokenId: text("token_id").primaryKey(),
  memberId: integer("member_id").notNull(),
  memberName: text("member_name").notNull(),
  factionId: integer("faction_id").notNull(),
  factionName: text("faction_name").notNull().default(""),
  tokenHash: text("token_hash").notNull(),
  createdAt: text("created_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  lastUsedAt: text("last_used_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  lastVerifiedAt: text("last_verified_at"),
  expiresAt: text("expires_at"),
  revokedAt: text("revoked_at"),
  revokedReason: text("revoked_reason"),
  lastQueueDepth: integer("last_queue_depth").notNull().default(0),
  lastDirectPushAt: text("last_direct_push_at"),
}, (table) => [index("idx_script_sync_faction_member").on(table.factionId, table.memberId, table.revokedAt, table.lastUsedAt)]);

export const eventObservers = sqliteTable("event_observers", {
  factionId: integer("faction_id").notNull(),
  eventKey: text("event_key").notNull(),
  observerTokenId: text("observer_token_id").notNull(),
  observerMemberId: integer("observer_member_id").notNull(),
  firstObservedAt: text("first_observed_at").notNull().default(sql`CURRENT_TIMESTAMP`),
  lastObservedAt: text("last_observed_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.eventKey, table.observerTokenId] })]);

export const syncTelemetry = sqliteTable("sync_telemetry", {
  factionId: integer("faction_id").notNull(),
  sourceKey: text("source_key").notNull(),
  lastSuccessAt: text("last_success_at"),
  lastObservationAt: text("last_observation_at"),
  queueDepth: integer("queue_depth").notNull().default(0),
  detailsJson: text("details_json").notNull().default("{}"),
  updatedAt: text("updated_at").notNull().default(sql`CURRENT_TIMESTAMP`),
}, (table) => [primaryKey({ columns: [table.factionId, table.sourceKey] })]);
