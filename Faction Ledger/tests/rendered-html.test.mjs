import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("defines the Blood Coven treasury product shell", async () => {
  const [tracker, layout, memberBalance] = await Promise.all([
    readFile(new URL("../app/BudgetTracker.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/MemberBalance.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(tracker, /Blood Coven Treasury/);
  assert.match(tracker, /Add proceeds/);
  assert.match(tracker, /Gross amount/);
  assert.match(tracker, /Player payout/);
  assert.match(tracker, /Settings/);
  assert.match(tracker, /Pending review/);
  assert.match(tracker, /Tax Rate/);
  assert.match(tracker, /Custom tax rate/);
  assert.match(tracker, /Estimated Pay/);
  assert.match(tracker, /Respect/);
  assert.match(tracker, /Torn API/);
  assert.match(tracker, /Install script/);
  assert.match(tracker, /Browser script not detected/);
  for (const tab of ["accounts", "balances", "armory", "wars", "ocs", "history"]) assert.match(tracker, new RegExp(`"${tab}"`));
  assert.match(tracker, /Direct deposit/);
  assert.match(tracker, /Balance requests/);
  assert.match(tracker, /cleanTornActivitySummary/);
  assert.match(tracker, /formatTornEventDate/);
  assert.match(tracker, /blood-coven-treasury\.user\.js/);
  assert.match(tracker, /stored only in this browser/);
  assert.match(layout, /title: "Blood Coven Treasury"/);
  assert.match(layout, /index: false/);
  assert.match(memberBalance, /Balance Request/);
  assert.match(memberBalance, /Request Full Balance/);
  assert.match(memberBalance, /Send if offline/);
  assert.match(memberBalance, /Send only if Online/);
  assert.match(memberBalance, /Send if Online or Travelling/);
  assert.match(memberBalance, /blood-coven-member-key/);
  assert.doesNotMatch(memberBalance, /Available faction balance/);
  assert.doesNotMatch(`${tracker}\n${layout}`, /codex-preview|react-loading-skeleton/);
});

test("declares durable budget storage and attributed transaction actions", async () => {
  const [hosting, route, tornRoute] = await Promise.all([
    readFile(new URL("../.openai/hosting.json", import.meta.url), "utf8"),
    readFile(new URL("../app/api/budget/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/torn/route.ts", import.meta.url), "utf8"),
  ]);
  assert.match(hosting, /"d1": "DB"/);
  for (const action of ["deposit", "directDeposit", "spend", "transfer", "setAllocations", "setPolicies"]) assert.match(route, new RegExp(`action === "${action}"`));
  assert.match(route, /actor_user_id/);
  assert.match(route, /playerPayout/);
  assert.match(route, /pendingWarId/);
  assert.match(route, /taxBpsOverride/);
  assert.match(route, /reviewed_tax_bps/);
  assert.match(tornRoute, /rankedwarreport/);
  assert.match(tornRoute, /market_price/);
  assert.match(tornRoute, /rankedwarhits,xantaken,refills/);
  assert.match(tornRoute, /Authorization: `ApiKey \$\{apiKey\}`/);
  assert.doesNotMatch(tornRoute, /INSERT[^;]+api.?key/is);
});

test("ships a private Torn userscript bridge and durable event ingestion", async () => {
  const [script, route, schema] = await Promise.all([
    readFile(new URL("../public/blood-coven-treasury.user.js", import.meta.url), "utf8"),
    readFile(new URL("../app/api/torn-browser/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../db/schema.ts", import.meta.url), "utf8"),
  ]);
  assert.match(script, /@match\s+https:\/\/www\.torn\.com\/\*/);
  assert.match(script, /blood-coven-treasury-bridge-v1/);
  assert.match(script, /GM_getValue/);
  assert.match(script, /xanax_use/);
  assert.match(script, /faction_payout/);
  assert.match(script, /member_balance_change/);
  assert.match(script, /Request faction balance/);
  assert.match(script, /bc-balance-label\">Faction:/);
  assert.match(script, /insertBefore\(entry, pointsLink\)/);
  assert.match(script, /classList\.contains\("bc-narrow"\)/);
  assert.match(script, /bc-request-button/);
  assert.match(script, /scanArmoryBalance/);
  assert.match(script, /and a balance of/);
  assert.match(script, /source: "armory"/);
  assert.match(script, /tab=armoury/);
  assert.match(script, /#faction-armoury/);
  assert.match(script, /#faction-crimes-root/);
  assert.match(script, /completedCrimeCards/);
  assert.match(script, /compactName/);
  assert.match(script, /findClassicMoneyRow/);
  assert.match(script, /\^Money:\?\$/);
  assert.match(script, /bc-wide-classic/);
  assert.match(script, /entryText/);
  assert.match(script, /completed and was distributed/);
  assert.match(script, /member_balance_snapshot/);
  assert.match(script, /oc_completion/);
  assert.match(script, /armory_movement/);
  assert.match(script, /armoryBalance/);
  assert.match(route, /INSERT OR IGNORE INTO torn_browser_events/);
  assert.match(route, /ranked_war_report/);
  assert.match(route, /normalizedBrowserOccurredAt/);
  assert.match(route, /Date\.parse\(b\.occurredAt/);
  assert.match(route, /oc_holdings/);
  assert.match(route, /armory_items/);
  assert.match(route, /member_balance_snapshot/);
  assert.match(schema, /torn_browser_events/);
  assert.match(schema, /ocHoldings/);
  assert.match(schema, /armoryItems/);
  assert.match(schema, /reviewedTaxBps/);
});
