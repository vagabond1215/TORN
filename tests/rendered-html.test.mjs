import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("defines the Blood Coven treasury product shell", async () => {
  const [tracker, layout] = await Promise.all([
    readFile(new URL("../app/BudgetTracker.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(tracker, /Blood Coven Treasury/);
  assert.match(tracker, /Add proceeds/);
  assert.match(tracker, /Gross amount/);
  assert.match(tracker, /Player payout/);
  assert.match(tracker, /Settings/);
  assert.match(tracker, /Pending review/);
  assert.match(tracker, /Torn API/);
  assert.match(tracker, /Install script/);
  assert.match(tracker, /Browser script not detected/);
  for (const tab of ["accounts", "history", "wars", "ocs"]) assert.match(tracker, new RegExp(`"${tab}"`));
  assert.match(tracker, /Direct deposit/);
  assert.match(tracker, /Payout requests/);
  assert.match(tracker, /blood-coven-treasury\.user\.js/);
  assert.match(tracker, /stored only in this browser/);
  assert.match(layout, /title: "Blood Coven Treasury"/);
  assert.match(layout, /index: false/);
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
  assert.match(script, /oc_credit/);
  assert.match(script, /Request faction balance/);
  assert.match(route, /INSERT OR IGNORE INTO torn_browser_events/);
  assert.match(route, /ranked_war_report/);
  assert.match(schema, /torn_browser_events/);
});
