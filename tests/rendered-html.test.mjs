import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("defines the faction ledger product shell", async () => {
  const [tracker, layout] = await Promise.all([
    readFile(new URL("../app/BudgetTracker.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
  ]);
  assert.match(tracker, /Faction Ledger/);
  assert.match(tracker, /Put every dollar/);
  assert.match(tracker, /Add proceeds/);
  assert.match(layout, /Faction Ledger — Torn City Budget Tracker/);
  assert.doesNotMatch(`${tracker}\n${layout}`, /codex-preview|react-loading-skeleton/);
});

test("declares durable budget storage and transaction actions", async () => {
  const [hosting, route] = await Promise.all([
    readFile(new URL("../.openai/hosting.json", import.meta.url), "utf8"),
    readFile(new URL("../app/api/budget/route.ts", import.meta.url), "utf8"),
  ]);
  assert.match(hosting, /"d1": "DB"/);
  for (const action of ["deposit", "spend", "transfer", "setAllocations"]) assert.match(route, new RegExp(`action === "${action}"`));
});
