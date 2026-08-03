// ==UserScript==
// @name         Blood Coven Treasury Bridge
// @namespace    https://faction-ledger-torn.vagabond1215.chatgpt.site/
// @version      1.1.2
// @description  Sends Blood Coven faction funds, Xanax use, and ranked-war activity to the private treasury when it is open.
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
    const matches = Array.from(text.matchAll(/(\d{2}:\d{2}:\d{2})\s*(\d{2}\/\d{2}\/\d{2})/g));
    const match = matches.at(-1);
    return match ? new Date(tornUnix(match[1], match[2]) * 1000).toISOString() : new Date().toISOString();
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

  function moneyValue(value) {
    return Number(String(value ?? "0").replace(/,/g, ""));
  }

  function scanFundsRow(text) {
    let match = text.match(/^(.+?) was given \$([\d,]+) by (.+?)(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (match) {
      addEvent("faction_payout", "funds", text, {
        recipientName: normalize(match[1]), amount: moneyValue(match[2]), actorName: normalize(match[3]), direction: "payout",
      });
      return;
    }

    match = text.match(/^(.+?) increased (.+?)'s Blood Coven money balance by \$([\d,]+) from \$([\d,]+) to \$([\d,]+) as (.+?)(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (match) {
      addEvent("oc_credit", "funds", text, {
        actorName: normalize(match[1]), memberName: normalize(match[2]), amount: moneyValue(match[3]),
        oldBalance: moneyValue(match[4]), newBalance: moneyValue(match[5]), detail: normalize(match[6]), direction: "credit", source: "oc",
      });
      return;
    }

    match = text.match(/^(.+?) deposited \$([\d,]+)(.*?)(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (match) addEvent("faction_deposit", "funds", text, { memberName: normalize(match[1]), amount: moneyValue(match[2]), detail: normalize(match[3]) });
  }

  function scanArmoryRow(text) {
    const used = text.match(/^(.+?) used one of the faction's (.+?) items(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (used) {
      const item = normalize(used[2]);
      addEvent(/^Xanax$/i.test(item) ? "xanax_use" : "armory", "armory", text, {
        memberName: normalize(used[1]), item, quantity: 1, action: "used",
      });
      return;
    }
    if (/(deposited \d+x|loaned \d+x|returned \d+x|filled one of the faction's)/i.test(text)) addEvent("armory", "armory", text);
  }

  function scanFactionPage() {
    if (location.pathname.toLowerCase() !== "/factions.php") return;
    const category = factionCategory();
    const rows = document.querySelectorAll("#react-root li, #factions li");
    for (const row of rows) {
      const text = normalize(row.textContent);
      if (text.length < 12 || text.length > 500 || !/\d{2}:\d{2}:\d{2}/.test(text)) continue;
      if (category === "armory") {
        scanArmoryRow(text);
      } else if (category === "funds") {
        scanFundsRow(text);
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
    addBalanceLink();
  }

  function addBalanceLink() {
    if (document.getElementById("blood-coven-balance-link")) return;
    const link = document.createElement("a");
    link.id = "blood-coven-balance-link";
    link.href = `${TREASURY_ORIGIN}/balance`;
    link.target = "_blank";
    link.rel = "noreferrer";
    link.textContent = "Request faction balance";
    link.title = "Verify your Blood Coven membership and request a payout";
    Object.assign(link.style, {
      position: "fixed", right: "18px", bottom: "18px", zIndex: "99999", padding: "9px 12px",
      border: "1px solid #6f1424", borderRadius: "4px", background: "#9f162b", color: "#fff",
      font: "700 12px Arial, sans-serif", textDecoration: "none", boxShadow: "0 3px 12px rgba(0,0,0,.32)",
    });
    document.body.appendChild(link);
  }

  function postToTreasury(kind, extra = {}) {
    window.postMessage({ channel: CHANNEL, kind, version: "1.1.2", ...extra }, TREASURY_ORIGIN);
  }

  function runTreasuryBridge() {
    function sendReady() {
      postToTreasury("ready", { pendingCount: queue().length });
      const events = queue().slice(0, 100);
      if (events.length) postToTreasury("events", { events });
    }
    window.addEventListener("message", (event) => {
      if (event.origin !== TREASURY_ORIGIN || event.data?.channel !== CHANNEL) return;
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
