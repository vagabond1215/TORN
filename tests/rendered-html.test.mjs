import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("defines the Blood Coven treasury product shell", async () => {
  const [tracker, layout] = await Promise.all([
    readFile(new URL("../app/BudgetTracker.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(tracker, /Blood Coven Treasury/);
  assert.match(tracker, /Guard the reserve/);
  assert.match(tracker, /Add proceeds/);
  assert.match(layout, /Blood Coven Treasury — Leadership Ledger/);
  assert.match(layout, /index: false/);
  assert.doesNotMatch(`${tracker}\n${layout}`, /codex-preview|react-loading-skeleton/);
});

test("declares durable budget storage and attributed transaction actions", async () => {
  const [hosting, route] = await Promise.all([
    readFile(new URL("../.openai/hosting.json", import.meta.url), "utf8"),
    readFile(new URL("../app/api/budget/route.ts", import.meta.url), "utf8"),
  ]);
  assert.match(hosting, /"d1": "DB"/);
  for (const action of ["deposit", "spend", "transfer", "setAllocations"]) assert.match(route, new RegExp(`action === "${action}"`));
  assert.match(route, /actor_user_id/);
  assert.match(route, /policy_bootstrap/);
});
