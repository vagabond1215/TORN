"use strict";

// Optional Chrome stress probe. See docs/native-validation-2026-11-27.md.
// A nonzero exit flags an observed violation or a probe execution error.
const assert = require("node:assert/strict");
const { randomUUID } = require("node:crypto");
const { readFile } = require("node:fs/promises");
const { createServer } = require("node:http");
const { join } = require("node:path");
const { chromium } = require("playwright-core");

const modules = ["training-recovery", "account-storage", "account-revisions",
  "account-calendar-lineage", "account-guarded-capture"];
const assets = new Map(modules.map(name => ["/" + name + ".js", name + ".js"]));
const server = createServer(async (request, response) => {
  if (request.url === "/") {
    response.writeHead(200, { "Content-Type": "text/html" });
    response.end("<!doctype html><title>TORN synthetic cross-tab probe</title>");
    return;
  }
  const asset = assets.get(request.url);
  if (!asset) {
    response.writeHead(404).end();
    return;
  }
  try {
    const body = await readFile(join(__dirname, "../..", asset));
    response.writeHead(200, { "Content-Type": "text/javascript" }).end(body);
  } catch {
    response.writeHead(500).end();
  }
});

async function probe(context, origin) {
  const tabs = await Promise.all([context.newPage(), context.newPage()]);
  const namespace = "torn-native-probe:" + randomUUID() + ":";
  await Promise.all(tabs.map(async tab => {
    await tab.goto(origin);
    for (const name of modules) await tab.addScriptTag({ url: origin + name + ".js" });
    await tab.evaluate(namespace => {
      const prefix = "torn-city-guide:", id = "999999910";
      const notes = prefix + "v1:profile:" + id + ":notes:gym";
      const names = () => Object.keys(localStorage).filter(key => key.startsWith(namespace));
      const store = {
        get length() { return names().length; },
        key: index => names()[index]?.slice(namespace.length) ?? null,
        getItem: key => localStorage.getItem(namespace + key),
        setItem: (key, value) => localStorage.setItem(namespace + key, value)
      };
      const locks = { request: (name, options, work) => navigator.locks.request(namespace + name, options, work) };
      const capture = mode => tornGuardedCapture.capture(store, id, () => true, locks, { mode });
      window.probe = {
        initialize: async () => {
          store.setItem(prefix + "activity-events:" + id, "[]");
          store.setItem(prefix + "activity-spend-ledger:" + id, "[]");
          store.setItem(notes, "before");
          const first = await capture("legacy");
          const lineage = await tornCalendarLineage.initialize(first, id);
          store.setItem(prefix + "calendar-lineage:v1:" + id, JSON.stringify(lineage));
        },
        edit: () => store.setItem(notes, "from second tab"),
        capture: async () => {
          const result = await capture("protected");
          return {
            changed: result.changed,
            entry: result.manifest.entries.find(entry => entry.section === "notes:gym")
          };
        }
      };
    }, namespace);
  }));
  const [a, b] = tabs;
  await a.evaluate(() => window.probe.initialize());
  await b.evaluate(() => window.probe.edit());
  return Promise.all(tabs.map(tab => tab.evaluate(() => window.probe.capture())));
}

async function main() {
  const trials = Number(process.argv[2] ?? 20);
  assert.ok(Number.isInteger(trials) && trials >= 1 && trials <= 100, "Use 1 to 100 trials");
  let browser;
  try {
    await new Promise((resolve, reject) => server.listen(0, "127.0.0.1", resolve).once("error", reject));
    const origin = "http://127.0.0.1:" + server.address().port + "/";
    browser = await chromium.launch({ channel: "chrome", ignoreDefaultArgs: ["--no-sandbox"] });
    let failures = 0;
    for (let i = 1; i <= trials; i++) {
      const context = await browser.newContext();
      try {
        const results = await probe(context, origin);
        if (results.filter(result => result.changed).length !== 1 ||
            results[0].entry.revision !== results[1].entry.revision) {
          failures++;
          console.log("Capture contention observed on trial " + i, JSON.stringify(results));
        }
      } catch (error) {
        failures++;
        console.error("Trial " + i + " failed", error.message);
      } finally {
        await context.close();
      }
    }
    console.log("Chrome " + browser.version() + ": " + (trials - failures) + "/" + trials + " clean trials");
    if (failures) process.exitCode = 1;
  } finally {
    try { await browser?.close(); }
    finally { await new Promise(resolve => server.close(resolve)); }
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
