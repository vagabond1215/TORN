// ==UserScript==
// @name         Blood Coven Treasury Bridge
// @namespace    https://faction-ledger-torn.vagabond1215.chatgpt.site/
// @version      1.1.4
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
  const BALANCE_STORE = "blood-coven-armory-balance-v1";
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
    scanArmoryBalance();
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

  function scanArmoryBalance() {
    const pageText = normalize(document.body.innerText);
    const match = pageText.match(/You have \$[\d,]+(?:\.\d{1,2})? and a balance of \$([\d,]+(?:\.\d{1,2})?)/i);
    if (!match) return;
    GM_setValue(BALANCE_STORE, {
      balance: moneyValue(match[1]),
      source: "armory",
      updatedAt: new Date().toISOString(),
    });
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
    addFactionBalance();
  }

  function balanceCache() {
    const value = GM_getValue(BALANCE_STORE, null);
    return value && typeof value === "object" && value.source === "armory" ? value : null;
  }

  function formatBalance(value, compact) {
    if (!Number.isFinite(Number(value))) return "—";
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: "USD",
      maximumFractionDigits: compact ? 2 : 0,
      notation: compact ? "compact" : "standard",
    }).format(Number(value));
  }

  function openBalancePopup() {
    window.open(
      `${TREASURY_ORIGIN}/balance`,
      "blood-coven-balance-request",
      "popup=yes,width=520,height=740,resizable=yes,scrollbars=yes,noopener,noreferrer",
    );
  }

  function ensureBalanceStyles() {
    if (document.getElementById("blood-coven-balance-styles")) return;
    const styles = document.createElement("style");
    styles.id = "blood-coven-balance-styles";
    styles.textContent = `
      #blood-coven-faction-balance { box-sizing: border-box; font-family: Arial, sans-serif; }
      #blood-coven-faction-balance .bc-faction-icon { width: 18px; height: 18px; flex: 0 0 18px; display: inline-flex; align-items: center; justify-content: center; border-radius: 50%; background: #8e1b2d; color: #fff; font-size: 10px; font-weight: 900; line-height: 1; box-shadow: inset 0 0 0 1px rgba(255,255,255,.18); }
      #blood-coven-faction-balance .bc-balance-value { white-space: nowrap; font-weight: 700; }
      #blood-coven-faction-balance.bc-narrow { min-width: 0; display: inline-flex; align-items: center; gap: 4px; padding: 0 5px; border: 0; background: transparent; color: inherit; cursor: pointer; font-size: 12px; }
      #blood-coven-faction-balance.bc-narrow .bc-balance-label,
      #blood-coven-faction-balance.bc-narrow .bc-request-button { display: none; }
      #blood-coven-faction-balance.bc-wide { width: 100%; display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 5px; padding: 2px 0; color: inherit; font-size: 12px; }
      #blood-coven-faction-balance.bc-wide .bc-faction-icon { display: none; }
      #blood-coven-faction-balance.bc-wide .bc-balance-label { font-weight: 700; }
      #blood-coven-faction-balance.bc-wide .bc-request-button { padding: 1px 5px; border: 1px solid #741524; border-radius: 3px; background: #971b31; color: #fff; cursor: pointer; font-size: 9px; font-weight: 700; line-height: 1.5; text-transform: lowercase; }
      #blood-coven-faction-balance.bc-wide-classic { width: 100%; min-height: 19px; display: flex !important; align-items: center; gap: 5px; padding: 0; color: inherit; font-size: 11px; line-height: 19px; }
      #blood-coven-faction-balance.bc-wide-classic .bc-faction-icon { display: none; }
      #blood-coven-faction-balance.bc-wide-classic .bc-balance-label { flex: 0 0 auto; font-weight: 700; }
      #blood-coven-faction-balance.bc-wide-classic .bc-balance-value { min-width: 0; flex: 1 1 auto; color: #7dcc26; }
      #blood-coven-faction-balance.bc-wide-classic .bc-request-button { flex: 0 0 auto; padding: 0 4px; border: 1px solid #555; border-radius: 2px; background: #333; color: #bbb; cursor: pointer; font-size: 9px; font-weight: 700; line-height: 15px; text-transform: lowercase; }
      #blood-coven-faction-balance:focus-visible,
      #blood-coven-faction-balance .bc-request-button:focus-visible { outline: 2px solid #d34b61; outline-offset: 2px; }
    `;
    document.head.appendChild(styles);
  }

  function resourceLink(label) {
    return Array.from(document.querySelectorAll("a")).find((link) => normalize(link.textContent).startsWith(`${label}:`));
  }

  function addModernFactionBalance() {
    const moneyLink = resourceLink("Money");
    const pointsLink = resourceLink("Points");
    if (!moneyLink || !pointsLink || !moneyLink.parentNode || !pointsLink.parentNode) return false;
    ensureBalanceStyles();

    let entry = document.getElementById("blood-coven-faction-balance");
    if (!entry) {
      entry = document.createElement("div");
      entry.id = "blood-coven-faction-balance";
      entry.innerHTML = '<span class="bc-faction-icon" aria-hidden="true">F</span><span class="bc-balance-label">Faction:</span><span class="bc-balance-value"></span><button class="bc-request-button" type="button">request</button>';
      entry.querySelector(".bc-request-button").addEventListener("click", openBalancePopup);
      entry.addEventListener("click", () => {
        if (entry.classList.contains("bc-narrow")) openBalancePopup();
      });
      entry.addEventListener("keydown", (event) => {
        if (entry.classList.contains("bc-narrow") && (event.key === "Enter" || event.key === " ")) {
          event.preventDefault();
          openBalancePopup();
        }
      });
    }

    const moneyBox = moneyLink.getBoundingClientRect();
    const pointsBox = pointsLink.getBoundingClientRect();
    const narrow = Math.abs(moneyBox.top - pointsBox.top) < 12;
    entry.classList.toggle("bc-narrow", narrow);
    entry.classList.toggle("bc-wide", !narrow);
    entry.tabIndex = narrow ? 0 : -1;
    entry.setAttribute("role", narrow ? "button" : "group");

    const cached = balanceCache();
    const amount = formatBalance(cached?.balance, narrow);
    entry.querySelector(".bc-balance-value").textContent = amount;
    entry.title = cached?.memberName
      ? `${cached.memberName}'s Blood Coven balance — click to request a payout`
      : "Visit the Blood Coven Armory once to load your faction balance";
    entry.setAttribute("aria-label", `Faction balance ${amount}. Request faction balance.`);

    if (narrow) pointsLink.parentNode.insertBefore(entry, pointsLink);
    else moneyLink.parentNode.insertBefore(entry, moneyLink.nextSibling);
    return true;
  }

  function findClassicMoneyRow() {
    const scope = document.querySelector("#sidebarroot, #sidebar, [class*='sidebar']") ?? document.body;
    const walker = document.createTreeWalker(scope, NodeFilter.SHOW_TEXT);
    let node = walker.nextNode();
    while (node) {
      if (/^Money:\s*$/i.test(normalize(node.nodeValue))) {
        const listRow = node.parentElement?.closest("li");
        if (listRow && normalize(listRow.textContent).length < 60) return listRow;
        let candidate = node.parentElement;
        let completeRow = null;
        while (candidate && candidate !== scope) {
          const text = normalize(candidate.textContent);
          if (/^Money:\s*\$[\d,]+/i.test(text) && text.length < 60) completeRow = candidate;
          if (text.length >= 60) break;
          candidate = candidate.parentElement;
        }
        if (completeRow) return completeRow;
      }
      node = walker.nextNode();
    }
    return null;
  }

  function addClassicFactionBalance() {
    const moneyRow = findClassicMoneyRow();
    if (!moneyRow?.parentNode) return;
    const tagName = moneyRow.tagName === "LI" ? "li" : "div";
    let entry = document.getElementById("blood-coven-faction-balance");
    if (!entry || entry.tagName.toLowerCase() !== tagName) {
      entry?.remove();
      entry = document.createElement(tagName);
      entry.id = "blood-coven-faction-balance";
      entry.innerHTML = '<span class="bc-faction-icon" aria-hidden="true">F</span><span class="bc-balance-label">Faction:</span><span class="bc-balance-value"></span><button class="bc-request-button" type="button">request</button>';
      entry.querySelector(".bc-request-button").addEventListener("click", openBalancePopup);
    }
    if (moneyRow.className && typeof moneyRow.className === "string") entry.className = moneyRow.className;
    entry.classList.add("bc-wide-classic");
    entry.setAttribute("role", "group");
    const cached = balanceCache();
    const amount = formatBalance(cached?.balance, false);
    entry.querySelector(".bc-balance-value").textContent = amount;
    entry.title = cached ? "Blood Coven Armory balance" : "Visit the Blood Coven Armory once to load your faction balance";
    entry.setAttribute("aria-label", `Faction balance ${amount}. Request faction balance.`);
    moneyRow.parentNode.insertBefore(entry, moneyRow.nextSibling);
  }

  function addFactionBalance() {
    ensureBalanceStyles();
    if (addModernFactionBalance()) return;
    addClassicFactionBalance();
  }

  function postToTreasury(kind, extra = {}) {
    window.postMessage({ channel: CHANNEL, kind, version: "1.1.4", ...extra }, TREASURY_ORIGIN);
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
