import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const script = readFileSync(new URL("../guide-features.js", import.meta.url), "utf8");
const now = 1795561750000;
const item = { item_id: 886, name: "Torn City Times", amount: 10 };
const trader = (id, price, extra = {}) => ({
  player_id: id, player_name: "Trader " + id, price, ...extra
});
const payload = (traders, generated_at = now / 1000) =>
  Response.json({ item_id: 886, traders, generated_at });

function fixture(fetchResponse, storage = new Map()) {
  let time = now;
  const calls = [];
  const handlers = {};
  const nodes = Object.fromEntries([
    "[data-inventory-detail]", "[data-query-buyers]", ".inventory-buyer-badge", ".inventory-buyer-status", ".inventory-buyer-results"
  ].map(selector => [selector, {}]));
  nodes["[data-inventory-detail]"].dataset = { inventoryDetail: "fixture" };
  nodes["[data-query-buyers]"].setAttribute = () => {};
  const row = { querySelectorAll: () => [], dataset: { buyerItem: "886", buyerQty: "10" }, querySelector: key => nodes[key] };
  nodes["[data-query-buyers]"].closest = () => row;
  const sandbox = vm.createContext({
    AbortSignal,
    Date: { now: () => time },
    document: {
      addEventListener: (type, handler) => { handlers[type] = handler; },
      querySelectorAll: () => [row]
    },
    localStorage: {
      getItem: key => storage.get(key) ?? null,
      setItem: (key, value) => storage.set(key, value)
    },
    tornGuidePreferences: { formatDate: timestamp => new Date(timestamp).toISOString() },
    fetch: async (...args) => {
      calls.push(args);
      return fetchResponse();
    }
  });
  const guide = vm.runInContext(script + "\n({ api:weav3rBuyers, render:inventoryDetailRow })", sandbox);
  const click = () => handlers.click({
    preventDefault: () => {}, target: { closest: selector => nodes[selector] }
  });
  return { ...guide, click, nodes, calls, storage, advance: ms => { time += ms; } };
}

test("only clicking Query Buyers sends a credential-free item request and renders sorted quotes", async () => {
  const f = fixture(() => payload([
    trader(14, 4100, { sponsored: 1 }),
    trader(23, 4700, { player_name: "<Public Trader>" }),
    trader(23, 4600)
  ]));
  const initial = f.render(item, "Tool", 0);
  assert.match(initial, /data-query-buyers/);
  assert.match(initial, /aria-label="Query Weav3r buyers for Torn City Times"/);
  assert.match(initial, /intent=sell&amp;item=886/);
  assert.doesNotMatch(initial, /inventory-buyer-icon/);
  assert.equal(f.calls.length, 0);
  await Promise.all([f.click(), f.click()]);
  assert.equal(f.calls.length, 1);
  const [[url, options]] = f.calls;
  assert.equal(url, "https://weav3r.dev/api/marketplace/886/traders?limit=10&sort=price");
  assert.equal(options.credentials, "omit");
  assert.equal(options.referrerPolicy, "no-referrer");
  assert.equal(options.headers, undefined);
  assert.match(f.nodes[".inventory-buyer-badge"].innerHTML, /inventory-buyer-icon/);
  const results = f.nodes[".inventory-buyer-results"].innerHTML;
  assert.match(results, /&lt;Public Trader&gt;.*\$4,700/);
  assert.match(results, /\$47,000.*if the buyer takes all 10/);
  assert.match(results, /Requested quantity is unknown/);
  assert.match(results, /pricelist\/23/);
  assert.match(results, /trade\.php#step=start&userID=23/);
  assert.match(results, /More pricelist buyers \(1\).*Trader 14.*Sponsored/);
});

test("empty results and stale cached quotes show no green indicator", async () => {
  const f = fixture(() => payload([trader(23, 4700)]));
  await f.click();
  const restored = fixture(() => payload([]), f.storage);
  assert.match(restored.render(item, "Tool", 0), /Last checked/);
  assert.match(restored.render(item, "Tool", 0), /inventory-buyer-icon/);
  restored.advance(300001);
  assert.match(restored.render(item, "Tool", 0), /Stale result/);
  assert.doesNotMatch(restored.render(item, "Tool", 0), /inventory-buyer-icon/);
  await restored.click();
  assert.match(restored.render(item, "Tool", 0), /No active pricelist buyers/);
  assert.doesNotMatch(restored.render(item, "Tool", 0), /inventory-buyer-icon/);
});

test("stale upstream timestamps and unresolved item IDs do not confirm availability", async () => {
  const f = fixture(() => payload([trader(23, 4700)], now / 1000 - 301));
  await f.api.query(886);
  assert.match(f.render(item, "Tool", 0), /Stale result/);
  assert.doesNotMatch(f.render(item, "Tool", 0), /inventory-buyer-icon/);
  assert.doesNotMatch(f.render({ name: "Unknown" }, "Tool", 0), /data-query-buyers/);
});

test("rate limiting uses the header when readable and a fallback when hidden", async () => {
  for (const [headers, cooldown] of [[{ "Retry-After": "9" }, 9], [{}, 60]]) {
    const f = fixture(() => new Response(null, { status: 429, headers }));
    await assert.rejects(f.api.query(886), new RegExp(cooldown + " seconds"));
    await assert.rejects(f.api.query(887), /rate limit/);
    assert.equal(f.calls.length, 1);
    f.advance(cooldown * 1000);
    await assert.rejects(f.api.query(886), /rate limit/);
    assert.equal(f.calls.length, 2);
  }
});

test("auth, CORS-style rejection and malformed responses preserve the cached result and manual link", async () => {
  for (const [respond, message] of [
    [() => new Response(null, { status: 401 }), /denied the public request/],
    [() => new Response(null, { status: 403 }), /denied the public request/],
    [() => { throw new TypeError("Failed to fetch"); }, /browser or network/],
    [() => Response.json({ item_id: 887, traders: [] }), /unexpected buyer response/]
  ]) {
    const initial = fixture(() => payload([trader(23, 4700)]));
    await initial.api.query(886);
    const f = fixture(respond, initial.storage);
    await f.click();
    assert.match(f.nodes[".inventory-buyer-status"].textContent, message);
    assert.match(f.render(item, "Tool", 0), /\$4,700.*Open Torn trade page/);
    assert.match(f.render(item, "Tool", 0), /Open Weav3r marketplace/);
  }
});
