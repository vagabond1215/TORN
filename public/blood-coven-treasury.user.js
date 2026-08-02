// ==UserScript==
// @name         Blood Coven Treasury Bridge
// @namespace    https://faction-ledger-torn.vagabond1215.chatgpt.site/
// @version      1.0.0
// @description  Sends Blood Coven faction news, armory activity, and ranked-war values to the private treasury when it is open.
// @author       Blood Coven
// @match        https://www.torn.com/*
// @match        https://faction-ledger-torn.vagabond1215.chatgpt.site/*
// @icon         https://www.torn.com/favicon.ico
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-idle
// @downloadURL  https://faction-ledger-torn.vagabond1215.chatgpt.site/blood-coven-treasury.user.js
// @updateURL    https://faction-ledger-torn.vagabond1215.chatgpt.site/blood-coven-treasury.user.js
// ==/UserScript==

(function () {
  "use strict";

  const TREASURY_ORIGIN = "https://faction-ledger-torn.vagabond1215.chatgpt.site";
  const CHANNEL = "blood-coven-treasury-bridge-v1";
  const QUEUE_KEY = "blood-coven-treasury-events-v1";
  const MAX_QUEUE = 300;

  function normalize(value) {
    return String(value ?? "").replace(/\s+/g, " ").trim();
  }

  function hash(value) {
    let result = 2166136261;
    for (let index = 0; index < value.length; index += 1) {
      result ^= value.charCodeAt(index);
      result = Math.imul(result, 16777619);
    }
    return (result >>> 0).toString(36);
  }

  function queue() {
    const value = GM_getValue(QUEUE_KEY, []);
    return Array.isArray(value) ? value : [];
  }

  function saveQueue(value) {
    GM_setValue(QUEUE_KEY, value.slice(-MAX_QUEUE));
  }

  function addEvent(eventType, category, summary, payload = {}, stableKey = "") {
    const cleanSummary = normalize(summary).slice(0, 500);
    if (!cleanSummary) return;
    const occurredAt = extractTimestamp(cleanSummary);
    const eventKey = `${eventType}:${stableKey || hash(`${category}|${cleanSummary}`)}`;
    const current = queue();
    if (current.some((event) => event.eventKey === eventKey)) return;
    current.push({ eventKey, eventType, category, occurredAt, summary: cleanSummary, sourceUrl: location.href, payload });
    saveQueue(current);
  }

  function extractTimestamp(text) {
    const match = text.match(/(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})/);
    return match ? `${match[2]} ${match[1]}` : new Date().toISOString();
  }

  function tornUnix(time, date) {
    const [hour, minute, second] = time.split(":").map(Number);
    const [day, month, shortYear] = date.split("/").map(Number);
    if (![hour, minute, second, day, month, shortYear].every(Number.isFinite)) return 0;
    return Math.floor(Date.UTC(2000 + shortYear, month - 1, day, hour, minute, second) / 1000);
  }

  function factionCategory() {
    const type = new URLSearchParams(location.search).get("type") ?? "1";
    return ({ "1": "main_news", "2": "attacking", "3": "funds", "4": "armory", "5": "crimes", "6": "membership" })[type] ?? "faction";
  }

  function scanFactionPage() {
    if (location.pathname.toLowerCase() !== "/factions.php") return;
    const category = factionCategory();
    const rows = document.querySelectorAll("#react-root li, #factions li");
    for (const row of rows) {
      const text = normalize(row.textContent);
      if (text.length < 12 || text.length > 500 || !/\d{2}:\d{2}:\d{2}/.test(text)) continue;
      if (category === "armory" && /(used one of the faction's|deposited \d+x|loaned \d+x|returned \d+x|filled one of the faction's)/i.test(text)) {
        addEvent("armory", category, text);
      } else if (category === "main_news" && /(ranked war|ranked up|ranked down|war mode)/i.test(text)) {
        addEvent("faction_news", category, text);
      }
    }
  }

  function scanRankedWarReport() {
    if (location.pathname.toLowerCase() !== "/war.php" || new URLSearchParams(location.search).get("step") !== "rankreport") return;
    const warId = Number(new URLSearchParams(location.search).get("rankID"));
    if (!warId) return;
    const heading = document.querySelector("#skip-to-content");
    const report = heading?.closest("main") ?? Array.from(document.querySelectorAll("main")).at(-1) ?? document.body;
    const text = normalize(report.textContent);
    if (!/Ranked War Report/i.test(text)) return;
    const valueMatch = text.match(/Blood Coven[\s\S]{0,800}?Total Value:\s*\$([\d,]+)/i);
    const winMatch = text.match(/Blood Coven has defeated (.+?) in a ranked war/i);
    const lossMatch = text.match(/(.+?) has defeated Blood Coven in a ranked war/i);
    const totalValue = Number((valueMatch?.[1] ?? "0").replace(/,/g, ""));
    const opponentName = normalize(winMatch?.[1] ?? lossMatch?.[1] ?? "Unknown faction").slice(0, 80);
    const reportTimes = Array.from(text.matchAll(/(\d{2}:\d{2}:\d{2})\s*-\s*(\d{2}\/\d{2}\/\d{2})/g));
    const finalTime = reportTimes.at(-1);
    const endedAt = finalTime ? tornUnix(finalTime[1], finalTime[2]) : Math.floor(Date.now() / 1000);
    if (!totalValue) return;
    addEvent("ranked_war_report", "war_report", `Ranked war #${warId} vs ${opponentName} — Total Value $${totalValue.toLocaleString("en-US")}`, {
      warId,
      opponentName,
      totalValue,
      won: Boolean(winMatch),
      endedAt,
    }, String(warId));
  }

  function scanTorn() {
    scanFactionPage();
    scanRankedWarReport();
  }

  function postToTreasury(kind, extra = {}) {
    window.postMessage({ channel: CHANNEL, kind, version: "1.0.0", ...extra }, TREASURY_ORIGIN);
  }

  function runTreasuryBridge() {
    function sendReady() {
      postToTreasury("ready", { pendingCount: queue().length });
      const events = queue().slice(0, 100);
      if (events.length) postToTreasury("events", { events });
    }
    window.addEventListener("message", (event) => {
      if (event.source !== window || event.origin !== TREASURY_ORIGIN || event.data?.channel !== CHANNEL) return;
      if (event.data.kind === "ping") sendReady();
      if (event.data.kind === "ack" && Array.isArray(event.data.eventKeys)) {
        const accepted = new Set(event.data.eventKeys.map(String));
        saveQueue(queue().filter((item) => !accepted.has(item.eventKey)));
        sendReady();
      }
    });
    sendReady();
    window.setInterval(sendReady, 15_000);
  }

  if (location.origin === TREASURY_ORIGIN) {
    runTreasuryBridge();
    return;
  }

  let scanTimer = 0;
  const scheduleScan = () => {
    window.clearTimeout(scanTimer);
    scanTimer = window.setTimeout(scanTorn, 800);
  };
  new MutationObserver(scheduleScan).observe(document.documentElement, { childList: true, subtree: true });
  scheduleScan();
  window.setInterval(scanTorn, 30_000);
})();
