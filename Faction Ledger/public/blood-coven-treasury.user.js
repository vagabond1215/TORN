// ==UserScript==
// @name         Blood Coven Treasury Bridge
// @namespace    https://faction-ledger-torn.vagabond1215.chatgpt.site/
// @version      1.4.0
// @description  Shares Blood Coven balance, Armory, OC, and ranked-war observations between verified faction users and the private treasury.
// @author       Blood Coven
// @match        https://www.torn.com/*
// @match        https://faction-ledger-torn.vagabond1215.chatgpt.site/*
// @icon         https://www.torn.com/favicon.ico
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_xmlhttpRequest
// @connect      faction-ledger-torn.vagabond1215.chatgpt.site
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
  const SERVER_BALANCE_STORE = "blood-coven-server-balance-v1";
  const SYNC_TOKEN_KEY = "blood-coven-script-sync-token-v1";
  const SYNC_API_KEY_KEY = "blood-coven-script-sync-api-key-v1";
  const SYNC_FACTION_KEY = "blood-coven-script-sync-faction-v1";
  const SYNC_SIGNOUT_KEY = "blood-coven-script-sync-signout-v1";
  const SCANNER_POSITION = "blood-coven-scanner-position-v1";
  const BLOOD_COVEN_ID = 52984;
  const MAX_QUEUE = 2000;
  let directSyncTimer = 0;
  let directSyncInFlight = false;
  let lastSyncAuthNotice = 0;

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
    const unique = [];
    const seen = new Set();
    for (let index = value.length - 1; index >= 0; index -= 1) {
      const event = value[index];
      if (!event?.eventKey || seen.has(event.eventKey)) continue;
      seen.add(event.eventKey);
      unique.push(event);
      if (unique.length >= MAX_QUEUE) break;
    }
    GM_setValue(QUEUE_KEY, unique.reverse());
  }

  function syncToken() {
    const value = String(GM_getValue(SYNC_TOKEN_KEY, "") ?? "");
    return /^bc1\.[a-f0-9]{32}\.[a-f0-9]{64}$/i.test(value) ? value : "";
  }

  function syncApiKey() {
    const value = String(GM_getValue(SYNC_API_KEY_KEY, "") ?? "").trim();
    return /^[A-Za-z0-9_-]{8,128}$/.test(value) ? value : "";
  }

  function syncFaction() {
    const value = GM_getValue(SYNC_FACTION_KEY, null);
    if (!value || typeof value !== "object") return null;
    const id = Number(value.id);
    const name = normalize(value.name);
    return Number.isSafeInteger(id) && id > 0 && name ? { id, name } : null;
  }

  function syncSignout() {
    const value = GM_getValue(SYNC_SIGNOUT_KEY, null);
    return value && typeof value === "object" ? value : null;
  }

  function clearFactionState(message, currentFaction = null, code = "signed_out") {
    saveQueue([]);
    GM_setValue(BALANCE_STORE, null);
    GM_setValue(SERVER_BALANCE_STORE, null);
    GM_setValue(SYNC_TOKEN_KEY, "");
    GM_setValue(SYNC_API_KEY_KEY, "");
    GM_setValue(SYNC_FACTION_KEY, null);
    GM_setValue(SYNC_SIGNOUT_KEY, {
      code,
      message: normalize(message) || "Faction sync was signed out.",
      currentFaction: currentFaction && typeof currentFaction === "object" ? currentFaction : null,
      at: new Date().toISOString(),
    });
    document.getElementById("blood-coven-faction-balance")?.remove();
  }

  function installSyncIdentity(token, apiKey, faction) {
    const cleanToken = String(token ?? "");
    const cleanApiKey = String(apiKey ?? "").trim();
    const factionId = Number(faction?.id);
    const factionName = normalize(faction?.name);
    if (!/^bc1\.[a-f0-9]{32}\.[a-f0-9]{64}$/i.test(cleanToken)) return false;
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(cleanApiKey)) return false;
    if (factionId !== BLOOD_COVEN_ID || factionName.toLowerCase() !== "blood coven") return false;

    saveQueue([]);
    GM_setValue(BALANCE_STORE, null);
    GM_setValue(SERVER_BALANCE_STORE, null);
    GM_setValue(SYNC_TOKEN_KEY, cleanToken);
    GM_setValue(SYNC_API_KEY_KEY, cleanApiKey);
    GM_setValue(SYNC_FACTION_KEY, { id: factionId, name: factionName });
    GM_setValue(SYNC_SIGNOUT_KEY, null);
    return true;
  }

  function syncBlocked() {
    return Boolean(syncSignout() && !syncToken());
  }

  function scheduleDirectSync(delay = 350) {
    if (location.origin !== "https://www.torn.com" || !syncToken() || !syncApiKey()) return;
    window.clearTimeout(directSyncTimer);
    directSyncTimer = window.setTimeout(() => { void directSync(); }, delay);
  }

  function addEvent(eventType, category, summary, payload = {}, stableKey = "", occurredAtOverride = "") {
    if (syncBlocked()) return false;
    const cleanSummary = normalize(summary).slice(0, 500);
    if (!cleanSummary) return false;
    const occurredAt = occurredAtOverride || extractTimestamp(cleanSummary);
    const eventKey = `${eventType}:${stableKey || hash(`${category}|${cleanSummary}`)}`;
    const current = queue();
    if (current.some((event) => event.eventKey === eventKey)) return false;
    current.push({ eventKey, eventType, category, occurredAt, summary: cleanSummary, sourceUrl: location.href, payload });
    saveQueue(current);
    scheduleDirectSync();
    return true;
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
    const pageHash = location.hash.toLowerCase();
    if (pageHash.includes("tab=crimes")) return "crimes";
    if (pageHash.includes("tab=armory")) return "armory";
    const type = new URLSearchParams(location.search).get("type") ?? "1";
    return ({ "1": "main_news", "2": "attacking", "3": "funds", "4": "armory", "5": "crimes", "6": "membership" })[type] ?? "faction";
  }

  function armoryCategory(value) {
    const text = normalize(value).toLowerCase().replace(/[_-]+/g, " ");
    if (/primary/.test(text)) return "primary";
    if (/secondary/.test(text)) return "secondary";
    if (/melee/.test(text)) return "melee";
    if (/temporary|\btemp\b/.test(text)) return "temporary";
    if (/\barmou?r\b/.test(text)) return "armor";
    if (/cloth/.test(text)) return "clothing";
    if (/medical|meds/.test(text)) return "medical";
    if (/drug/.test(text)) return "drugs";
    if (/booster/.test(text)) return "boosters";
    if (/candy|alcohol|energy drink|consumable/.test(text)) return "consumables";
    if (/utility|tools?|materials?|enhancer/.test(text)) return "utility";
    if (/special/.test(text)) return "special";
    return "other";
  }

  function currentArmoryCategory() {
    const controls = Array.from(document.querySelectorAll("[role='tab'], button, a"));
    const active = controls.find((control) => {
      const selected = control.getAttribute("aria-selected") === "true" || /(^|\s)(active|selected|current)(\s|$)/i.test(String(control.className ?? ""));
      return selected && armoryCategory(control.textContent) !== "other";
    });
    if (active) return armoryCategory(active.textContent);
    const pageText = normalize(document.body.innerText).slice(0, 2500);
    const heading = pageText.match(/(?:Armory|Armoury)\s*(?:-|—|:)?\s*(Primary|Secondary|Melee|Temporary|Temp|Armor|Armour|Clothing|Medical|Drugs?|Boosters?|Consumables?|Utility|Special)/i);
    return armoryCategory(heading?.[1] ?? "other");
  }

  function moneyValue(value) {
    return Number(String(value ?? "0").replace(/[$,\s]/g, ""));
  }

  function entryText(row) {
    const timedControl = Array.from(row.querySelectorAll("button, [role='button']"))
      .map((control) => normalize(control.textContent))
      .filter((text) => /\d{2}:\d{2}:\d{2}\s+\d{2}\/\d{2}\/\d{2}/.test(text))
      .sort((a, b) => a.length - b.length)[0];
    return normalize(timedControl || row.textContent)
      .replace(/\s+(?:Copy info|CopySave|Save news).*$/i, "")
      .trim();
  }

  function scanFundsRow(text) {
    let match = text.match(/^(.+?) was given \$([\d,]+) by (.+?)(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (match) {
      addEvent("faction_payout", "funds", text, {
        recipientName: normalize(match[1]), amount: moneyValue(match[2]), actorName: normalize(match[3]), direction: "payout",
      });
      return;
    }

    match = text.match(/^(.+?) (increased|decreased) (.+?)'s Blood Coven money balance by \$([\d,]+) from \$([\d,]+) to \$([\d,]+) as (.+?)(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (match) {
      const direction = match[2].toLowerCase() === "decreased" ? "decrease" : "increase";
      const detail = normalize(match[7]);
      addEvent("member_balance_change", "funds", text, {
        actorName: normalize(match[1]), memberName: normalize(match[3]), amount: moneyValue(match[4]),
        oldBalance: moneyValue(match[5]), newBalance: moneyValue(match[6]), detail, direction,
      });
      const oc = direction === "increase" ? detail.match(/their ([\d.]+)% cut .*? in the faction's (.+?) scenario/i) : null;
      if (oc) {
        const percent = Number(oc[1]);
        const crimeName = normalize(oc[2]);
        const cashAmount = percent > 0 ? Math.round(moneyValue(match[4]) * 100 / percent) : 0;
        const completedAt = `${match[8]} ${match[9]}`;
        addEvent("oc_completion", "funds", `${crimeName} completed and was distributed for approximately $${cashAmount.toLocaleString("en-US")} ${completedAt}`, {
          crimeName, success: true, status: "distributed", cashAmount, items: [], source: "funds",
        }, hash(`${crimeName}|${completedAt}`));
      }
      return;
    }

    match = text.match(/^(.+?) deposited \$([\d,]+)(.*?)(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (match) addEvent("faction_deposit", "funds", text, { memberName: normalize(match[1]), amount: moneyValue(match[2]), detail: normalize(match[3]) });
  }

  function scanArmoryRow(text, category = currentArmoryCategory()) {
    const used = text.match(/^(.+?) used one of the faction's (.+?) items(\d{2}:\d{2}:\d{2})\s+(\d{2}\/\d{2}\/\d{2})$/i);
    if (used) {
      const item = normalize(used[2]);
      addEvent(/^Xanax$/i.test(item) ? "xanax_use" : "armory_movement", "armory", text, {
        memberName: normalize(used[1]), item, quantity: 1, action: "used", category,
      });
      return;
    }
    const movement = text.match(/^(.+?) (deposited|loaned|returned) (\d+)x (.+?)(?=\d{2}:\d{2}:\d{2})/i);
    if (movement) {
      const action = movement[2].toLowerCase();
      const item = normalize(movement[4].replace(/\s+(?:to|into|from)\s+the faction.*$/i, ""));
      addEvent("armory_movement", "armory", text, {
        memberName: normalize(movement[1]), action, quantity: Number(movement[3]), item, category,
      });
      return;
    }
    if (/filled one of the faction's/i.test(text)) addEvent("armory", "armory", text);
  }

  function scanFundBalances(force = false) {
    if (!force && factionCategory() !== "funds") return 0;
    const members = new Map();
    const rows = document.querySelectorAll("#react-root tr, #factions tr, #react-root li, #factions li");
    for (const row of rows) {
      const text = normalize(row.textContent);
      if (!text || /\d{2}:\d{2}:\d{2}/.test(text)) continue;
      const profile = row.querySelector('a[href*="profiles.php"]');
      const name = normalize(profile?.textContent);
      const amounts = Array.from(text.matchAll(/\$([\d,]+)/g));
      if (!name || amounts.length === 0 || name.length > 80) continue;
      members.set(name, moneyValue(amounts.at(-1)[1]));
    }
    if (members.size === 0) return 0;
    const snapshot = Array.from(members, ([name, balance]) => ({ name, balance })).sort((a, b) => a.name.localeCompare(b.name));
    const bucket = Math.floor(Date.now() / 300_000);
    addEvent("member_balance_snapshot", "funds", `Faction balance snapshot (${snapshot.length} members)`, { members: snapshot }, `${hash(JSON.stringify(snapshot))}:${bucket}`);
    return snapshot.length;
  }

  function crimeIdFromRow(row) {
    const links = Array.from(row.querySelectorAll("a[href]"));
    for (const link of links) {
      const href = link.getAttribute("href") ?? "";
      const match = href.match(/(?:crime(?:id)?=|crime\/)(\d+)/i) || href.match(/[?&#](?:id|crime)=(\d+)/i);
      if (match) return Number(match[1]);
    }
    const dataId = row.getAttribute("data-crime-id") || row.querySelector("[data-crime-id]")?.getAttribute("data-crime-id");
    return Number(dataId) || 0;
  }

  function scanCrimeRow(row, text) {
    if (text.length < 12 || text.length > 5000 || !/(success|successful|completed|reward|received|earned|failed|failure)/i.test(text)) return false;
    const heading = row.querySelector("h2, h3, h4, strong, [class*='title'], [class*='name'], [class*='scenario']");
    const crimeName = normalize(heading?.textContent || text.split(/(?:success|successful|completed|failed|failure)/i)[0]).slice(0, 100) || "Organized crime";
    const cashValues = Array.from(text.matchAll(/\$([\d,]+)/g)).map((item) => moneyValue(item[1]));
    const itemMatches = [
      ...Array.from(text.matchAll(/(\d+)\s*x\s+([A-Za-z][A-Za-z0-9 '&-]{2,70}?)(?=,|\.|\$|\d{2}:|$)/gi)).map((item) => ({ quantity: Number(item[1]), name: normalize(item[2]) })),
      ...Array.from(text.matchAll(/([A-Za-z][A-Za-z0-9 '&-]{2,70}?)\s*x\s*(\d+)(?=,|\.|\$|\d{2}:|$)/gi)).map((item) => ({ quantity: Number(item[2]), name: normalize(item[1]) })),
    ];
    const items = Array.from(new Map(itemMatches.filter((item) => item.quantity > 0).map((item) => [item.name.toLowerCase(), item])).values());
    const crimeId = crimeIdFromRow(row);
    const success = !/(failed|failure)/i.test(text);
    const stableKey = crimeId ? String(crimeId) : hash(text);
    return addEvent("oc_completion", "crimes", text, {
      crimeId: crimeId || undefined, crimeName, success, status: "held",
      cashAmount: cashValues.length ? Math.max(...cashValues) : 0, items,
    }, stableKey);
  }

  function scanCrimeCards(force = false) {
    if (!force && factionCategory() !== "crimes") return 0;
    const scope = document.querySelector("#react-root, #factions") ?? document.body;
    const candidates = Array.from(scope.querySelectorAll("article, li, tr, [class*='crime'], [class*='result'], [class*='scenario'], [data-crime-id]"))
      .map((row) => ({ row, text: normalize(row.textContent) }))
      .filter(({ text }) => text.length >= 12 && text.length <= 5000 && /(success|successful|completed|failed|failure)/i.test(text))
      .sort((a, b) => a.text.length - b.text.length);
    const cards = [];
    for (const candidate of candidates) {
      if (cards.some((card) => candidate.row.contains(card.row))) continue;
      cards.push(candidate);
    }
    let found = 0;
    for (const card of cards) if (scanCrimeRow(card.row, card.text)) found += 1;
    return found;
  }

  function itemNameFromRow(row) {
    const image = Array.from(row.querySelectorAll("img[alt]"))
      .map((img) => normalize(img.getAttribute("alt")))
      .find((value) => value && value.length <= 100 && !/blood coven|avatar|icon|logo/i.test(value));
    if (image) return image;
    const named = row.querySelector("[data-item-name], [class*='itemName'], [class*='item-name'], [class*='name']");
    const namedValue = normalize(named?.getAttribute("data-item-name") || named?.textContent);
    if (namedValue && namedValue.length <= 100 && !/^\d+$/.test(namedValue)) return namedValue;
    const title = Array.from(row.querySelectorAll("[title]"))
      .map((element) => normalize(element.getAttribute("title")))
      .find((value) => value && value.length <= 100 && !/give|loan|deposit|remove|view/i.test(value));
    return title || "";
  }

  function quantityFromRow(row, name) {
    const quantityNode = row.querySelector("[data-quantity], [class*='quantity'], [class*='qty'], [class*='stock'], [class*='amount']");
    const nodeValue = normalize(quantityNode?.getAttribute("data-quantity") || quantityNode?.textContent);
    const nodeNumber = nodeValue.match(/[\d,]+/);
    if (nodeNumber) return Number(nodeNumber[0].replace(/,/g, ""));
    const text = normalize(row.textContent).replace(name, " ");
    const patterns = [
      /(?:quantity|qty|stock|available|owned)\s*:?\s*([\d,]+)/i,
      /\bx\s*([\d,]+)\b/i,
      /\b([\d,]+)\s*x\b/i,
    ];
    for (const pattern of patterns) {
      const match = text.match(pattern);
      if (match) return Number(match[1].replace(/,/g, ""));
    }
    return Number.NaN;
  }

  function scanArmoryInventory(force = false) {
    const pageLooksArmory = factionCategory() === "armory" || /faction\s+(?:armory|armoury)|(?:armory|armoury)\s+items/i.test(normalize(document.body.innerText).slice(0, 4000));
    if (!force && !pageLooksArmory) return { category: "other", items: 0 };
    if (force && !pageLooksArmory && location.pathname.toLowerCase() !== "/factions.php") return { category: "other", items: 0 };
    const category = currentArmoryCategory();
    if (category === "other" && !pageLooksArmory) return { category, items: 0 };
    const scope = document.querySelector("#react-root, #factions") ?? document.body;
    const rows = Array.from(scope.querySelectorAll("tr, li, [class*='item'], [class*='armory'], [class*='armoury']"));
    const found = new Map();
    for (const row of rows) {
      const text = normalize(row.textContent);
      if (!text || /\d{2}:\d{2}:\d{2}\s+\d{2}\/\d{2}\/\d{2}/.test(text)) continue;
      const name = itemNameFromRow(row);
      if (!name) continue;
      const quantity = quantityFromRow(row, name);
      if (!Number.isSafeInteger(quantity) || quantity < 0 || quantity > 1_000_000_000) continue;
      const existing = found.get(name.toLowerCase());
      if (!existing || quantity > existing.quantity) found.set(name.toLowerCase(), { name, quantity, category });
    }
    const items = Array.from(found.values()).sort((a, b) => a.name.localeCompare(b.name));
    if (!items.length) return { category, items: 0 };
    const observedAt = new Date().toISOString();
    const bucket = Math.floor(Date.now() / 300_000);
    addEvent("armory_snapshot", "armory", `Armory ${category} snapshot (${items.length} item types)`, { category, items }, `snapshot:${category}:${hash(JSON.stringify(items))}:${bucket}`, observedAt);
    return { category, items: items.length };
  }

  function scanFactionPage(force = false) {
    if (location.pathname.toLowerCase() !== "/factions.php" && !force) return;
    scanArmoryBalance();
    const category = factionCategory();
    if (category === "funds" || force) scanFundBalances(force);
    if (category === "crimes" || force) scanCrimeCards(force);
    const activeArmoryCategory = currentArmoryCategory();
    const rows = document.querySelectorAll("#react-root li, #factions li, #react-root tr, #factions tr");
    for (const row of rows) {
      const text = entryText(row);
      if (text.length < 12 || text.length > 800 || !/\d{2}:\d{2}:\d{2}/.test(text)) continue;
      if (category === "armory") scanArmoryRow(text, activeArmoryCategory);
      else if (category === "funds") scanFundsRow(text);
      else if (category === "main_news" && /(ranked war|ranked up|ranked down|war mode)/i.test(text)) addEvent("faction_news", category, text);
      else if (force) {
        scanFundsRow(text);
        scanArmoryRow(text, activeArmoryCategory);
      }
    }
  }

  function scanArmoryBalance() {
    if (syncBlocked()) return false;
    const pageText = normalize(document.body.innerText);
    const match = pageText.match(/You have \$[\d,]+(?:\.\d{1,2})? and a balance of \$([\d,]+(?:\.\d{1,2})?)/i);
    if (!match) return false;
    GM_setValue(BALANCE_STORE, {
      balance: moneyValue(match[1]),
      source: "armory",
      updatedAt: new Date().toISOString(),
    });
    scheduleDirectSync();
    return true;
  }

  function scanRankedWarReport() {
    if (location.pathname.toLowerCase() !== "/war.php" || new URLSearchParams(location.search).get("step") !== "rankreport") return 0;
    const warId = Number(new URLSearchParams(location.search).get("rankID"));
    if (!warId) return 0;
    const heading = document.querySelector("#skip-to-content");
    const report = heading?.closest("main") ?? Array.from(document.querySelectorAll("main")).at(-1) ?? document.body;
    const text = normalize(report.textContent);
    if (!/Ranked War Report/i.test(text)) return 0;
    const valueMatch = text.match(/Blood Coven[\s\S]{0,1200}?Total Value:\s*\$([\d,]+)/i);
    const winMatch = text.match(/Blood Coven has defeated (.+?) in a ranked war/i);
    const lossMatch = text.match(/(.+?) has defeated Blood Coven in a ranked war/i);
    const totalValue = Number((valueMatch?.[1] ?? "0").replace(/,/g, ""));
    const opponentName = normalize(winMatch?.[1] ?? lossMatch?.[1] ?? "Unknown faction").slice(0, 80);
    const reportTimes = Array.from(text.matchAll(/(\d{2}:\d{2}:\d{2})\s*-\s*(\d{2}\/\d{2}\/\d{2})/g));
    const finalTime = reportTimes.at(-1);
    const endedAt = finalTime ? tornUnix(finalTime[1], finalTime[2]) : Math.floor(Date.now() / 1000);
    if (!totalValue) return 0;
    return addEvent("ranked_war_report", "war_report", `Ranked war #${warId} vs ${opponentName} — Total Value $${totalValue.toLocaleString("en-US")}`, {
      warId, opponentName, totalValue, won: Boolean(winMatch), endedAt,
    }, String(warId)) ? 1 : 0;
  }

  function scanTorn() {
    if (syncBlocked()) {
      document.getElementById("blood-coven-faction-balance")?.remove();
      return;
    }
    scanFactionPage();
    scanRankedWarReport();
    addFactionBalance();
  }

  function armoryBalanceCache() {
    const value = GM_getValue(BALANCE_STORE, null);
    return value && typeof value === "object" && value.source === "armory" ? value : null;
  }

  function serverBalanceCache() {
    const value = GM_getValue(SERVER_BALANCE_STORE, null);
    return value && typeof value === "object" && value.source === "server" ? value : null;
  }

  function balanceCache() {
    const local = armoryBalanceCache();
    const server = serverBalanceCache();
    if (!local) return server;
    if (!server) return local;
    const localTime = Date.parse(local.updatedAt ?? "") || 0;
    const serverTime = Date.parse(server.updatedAt ?? "") || 0;
    return serverTime >= localTime ? server : local;
  }

  function formatBalance(value, compact) {
    if (!Number.isFinite(Number(value))) return "—";
    return new Intl.NumberFormat("en-US", {
      style: "currency", currency: "USD", maximumFractionDigits: compact ? 2 : 0, notation: compact ? "compact" : "standard",
    }).format(Number(value));
  }

  function openBalancePopup() {
    window.open(`${TREASURY_ORIGIN}/balance`, "blood-coven-balance-request", "popup=yes,width=520,height=740,resizable=yes,scrollbars=yes,noopener,noreferrer");
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
      #blood-coven-faction-balance.bc-narrow .bc-balance-label, #blood-coven-faction-balance.bc-narrow .bc-request-button { display: none; }
      #blood-coven-faction-balance.bc-wide { width: 100%; display: grid; grid-template-columns: auto 1fr auto; align-items: center; gap: 5px; padding: 2px 0; color: inherit; font-size: 12px; }
      #blood-coven-faction-balance.bc-wide .bc-faction-icon { display: none; }
      #blood-coven-faction-balance.bc-wide .bc-balance-label { font-weight: 700; }
      #blood-coven-faction-balance.bc-wide .bc-request-button { padding: 1px 5px; border: 1px solid #741524; border-radius: 3px; background: #971b31; color: #fff; cursor: pointer; font-size: 9px; font-weight: 700; line-height: 1.5; text-transform: lowercase; }
      #blood-coven-faction-balance.bc-wide-classic { width: 100%; min-height: 19px; display: flex !important; align-items: center; gap: 5px; padding: 0; color: inherit; font-size: 11px; line-height: 19px; }
      #blood-coven-faction-balance.bc-wide-classic .bc-faction-icon { display: none; }
      #blood-coven-faction-balance.bc-wide-classic .bc-balance-label { flex: 0 0 auto; font-weight: 700; }
      #blood-coven-faction-balance.bc-wide-classic .bc-balance-value { min-width: 0; flex: 1 1 auto; color: #7dcc26; }
      #blood-coven-faction-balance.bc-wide-classic .bc-request-button { flex: 0 0 auto; padding: 0 4px; border: 1px solid #555; border-radius: 2px; background: #333; color: #bbb; cursor: pointer; font-size: 9px; font-weight: 700; line-height: 15px; text-transform: lowercase; }
      #blood-coven-faction-balance:focus-visible, #blood-coven-faction-balance .bc-request-button:focus-visible { outline: 2px solid #d34b61; outline-offset: 2px; }
    `;
    document.head.appendChild(styles);
  }

  function resourceLink(label) {
    return Array.from(document.querySelectorAll("a")).find((link) => normalize(link.textContent).startsWith(`${label}:`));
  }

  function addModernFactionBalance() {
    if (syncBlocked()) return false;
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
      entry.addEventListener("click", () => { if (entry.classList.contains("bc-narrow")) openBalancePopup(); });
      entry.addEventListener("keydown", (event) => {
        if (entry.classList.contains("bc-narrow") && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); openBalancePopup(); }
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
    entry.title = cached?.memberName ? `${cached.memberName}'s Blood Coven balance — click to request a payout` : cached?.source === "server" ? "Blood Coven balance synchronized from the faction ledger" : "Visit the Blood Coven Armory once or verify the balance page to load your faction balance";
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
      if (/^Money:?$/i.test(normalize(node.nodeValue))) {
        const listRow = node.parentElement?.closest("li");
        if (listRow && /^Money:\s*\$[\d,]+/i.test(normalize(listRow.textContent)) && normalize(listRow.textContent).length < 60) return listRow;
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
    if (syncBlocked()) return;
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
    entry.title = cached?.source === "server" ? "Blood Coven balance synchronized from the faction ledger" : cached ? "Blood Coven Armory balance" : "Open the Blood Coven balance page to connect live sync";
    entry.setAttribute("aria-label", `Faction balance ${amount}. Request faction balance.`);
    moneyRow.parentNode.insertBefore(entry, moneyRow.nextSibling);
  }

  function addFactionBalance() {
    if (syncBlocked()) {
      document.getElementById("blood-coven-faction-balance")?.remove();
      return;
    }
    ensureBalanceStyles();
    if (addModernFactionBalance()) return;
    addClassicFactionBalance();
  }

  function directRequest(method, path, body) {
    return new Promise((resolve, reject) => {
      const token = syncToken();
      const apiKey = syncApiKey();
      if (!token || !apiKey) { reject(new Error("Userscript sync is not connected.")); return; }
      GM_xmlhttpRequest({
        method,
        url: `${TREASURY_ORIGIN}${path}`,
        headers: {
          Authorization: `Bearer ${token}`,
          "X-Torn-Api-Key": apiKey,
          Accept: "application/json",
          ...(body ? { "Content-Type": "application/json" } : {}),
        },
        data: body ? JSON.stringify(body) : undefined,
        timeout: 12_000,
        onload(response) {
          let payload = {};
          try { payload = response.responseText ? JSON.parse(response.responseText) : {}; } catch { payload = {}; }
          if (response.status >= 200 && response.status < 300) { resolve(payload); return; }
          const error = new Error(payload.error || `Treasury sync failed (${response.status}).`);
          error.status = response.status;
          error.code = payload.code || "";
          error.currentFaction = payload.currentFaction || null;
          reject(error);
        },
        ontimeout() { reject(new Error("Treasury sync timed out.")); },
        onerror() { reject(new Error("Treasury sync could not reach the server.")); },
      });
    });
  }

  function applyServerBalance(payload) {
    const storedFaction = syncFaction();
    const responseFactionId = Number(payload?.faction?.id);
    if (storedFaction && responseFactionId && responseFactionId !== storedFaction.id) {
      clearFactionState("The server returned a different faction identity, so the local Blood Coven cache was cleared.", payload?.faction ?? null, "faction_changed");
      return;
    }
    const balance = Number(payload?.balance);
    const memberName = normalize(payload?.member?.name);
    if (!Number.isSafeInteger(balance) || balance < 0 || balance > 1_000_000_000_000 || !memberName) return;
    const updatedAt = String(payload.observedAt || payload.updatedAt || payload.serverTime || new Date().toISOString());
    GM_setValue(SERVER_BALANCE_STORE, { balance, memberName, source: "server", updatedAt });
    addFactionBalance();
  }

  async function directSync() {
    if (location.origin !== "https://www.torn.com" || directSyncInFlight || !syncToken() || !syncApiKey()) return false;
    directSyncInFlight = true;
    try {
      const state = await directRequest("GET", "/api/script-sync");
      applyServerBalance(state);
      if (!syncToken()) return false;

      const pending = queue().slice(0, 100);
      if (pending.length) {
        const imported = await directRequest("POST", "/api/torn-browser", { events: pending });
        const accepted = new Set(Array.isArray(imported.acceptedKeys) ? imported.acceptedKeys.map(String) : []);
        if (accepted.size) saveQueue(queue().filter((item) => !accepted.has(item.eventKey)));
      }
      if (queue().length) scheduleDirectSync(900);
      return true;
    } catch (error) {
      const status = Number(error?.status);
      if (status === 401) {
        const currentFaction = error?.currentFaction && typeof error.currentFaction === "object" ? error.currentFaction : null;
        clearFactionState(
          error instanceof Error ? error.message : "Blood Coven membership changed; live sync was signed out.",
          currentFaction,
          String(error?.code || "invalid_session"),
        );
        const now = Date.now();
        if (now - lastSyncAuthNotice > 60_000) {
          lastSyncAuthNotice = now;
          scannerToast(currentFaction?.name
            ? `Blood Coven sync signed out: Torn now reports ${normalize(currentFaction.name)}. Old faction cache and queued observations were cleared.`
            : "Blood Coven sync signed out because membership could not be confirmed. Old faction cache and queued observations were cleared.", true);
        }
      } else if (status === 503) {
        const now = Date.now();
        if (now - lastSyncAuthNotice > 60_000) {
          lastSyncAuthNotice = now;
          scannerToast("Torn membership verification is temporarily unavailable. Existing local state was retained and sync will retry automatically.", true);
        }
      }
      return false;
    } finally {
      directSyncInFlight = false;
    }
  }

  function postToTreasury(kind, extra = {}) {
    window.postMessage({ channel: CHANNEL, kind, version: "1.4.0", ...extra }, TREASURY_ORIGIN);
  }

  function runTreasuryBridge() {
    function sendReady() {
      postToTreasury("ready", {
        pendingCount: queue().length,
        syncTokenReady: Boolean(syncToken() && syncApiKey()),
        syncIdentityCleared: syncSignout(),
      });
      postToTreasury("armoryBalance", { balance: armoryBalanceCache() });
      const events = syncBlocked() ? [] : queue().slice(0, 100);
      if (events.length) postToTreasury("events", { events });
    }
    window.addEventListener("message", (event) => {
      if (event.origin !== TREASURY_ORIGIN || event.data?.channel !== CHANNEL) return;
      if (event.data.kind === "ping") sendReady();
      if (event.data.kind === "installSyncToken") {
        if (installSyncIdentity(event.data.token, event.data.apiKey, event.data.faction)) {
          postToTreasury("syncTokenInstalled");
          sendReady();
        }
      }
      if (event.data.kind === "clearSyncIdentity") {
        clearFactionState(String(event.data.message ?? "Signed out from the Blood Coven balance page."), null, "manual_signout");
        postToTreasury("syncIdentityCleared", { message: String(event.data.message ?? "Signed out.") });
        sendReady();
      }
      if (event.data.kind === "ack" && Array.isArray(event.data.eventKeys)) {
        const accepted = new Set(event.data.eventKeys.map(String));
        saveQueue(queue().filter((item) => !accepted.has(item.eventKey)));
        sendReady();
      }
    });
    sendReady();
    window.setInterval(sendReady, 15_000);
  }

  function scannerToast(message, problem = false) {
    let toast = document.getElementById("blood-coven-scan-toast");
    if (!toast) {
      toast = document.createElement("div");
      toast.id = "blood-coven-scan-toast";
      Object.assign(toast.style, {
        position: "fixed", zIndex: "2147483647", left: "50%", bottom: "24px", transform: "translateX(-50%)",
        maxWidth: "520px", padding: "9px 12px", borderRadius: "8px", font: "600 12px/1.4 Arial,sans-serif",
        color: "#fff", boxShadow: "0 4px 20px rgba(0,0,0,.35)", pointerEvents: "none",
      });
      document.body.appendChild(toast);
    }
    toast.style.background = problem ? "#7e2020" : "#252525";
    toast.textContent = message;
    toast.style.opacity = "1";
    window.clearTimeout(Number(toast.dataset.timer || 0));
    const timer = window.setTimeout(() => { toast.style.opacity = "0"; }, 5200);
    toast.dataset.timer = String(timer);
  }

  function manualScan() {
    if (syncBlocked()) {
      const signout = syncSignout();
      const bridge = window.open(`${TREASURY_ORIGIN}/balance`, "blood-coven-balance-request", "popup=yes,width=520,height=740,resizable=yes,scrollbars=yes");
      scannerToast(`${normalize(signout?.message) || "Faction sync is signed out."} ${bridge ? "Verify current Blood Coven membership in the balance window to start with a clean cache." : "Open the Blood Coven balance page to verify current membership."}`, true);
      return;
    }
    const before = queue().length;
    const ocs = scanCrimeCards(true);
    const armory = scanArmoryInventory(true);
    const war = scanRankedWarReport();
    scanFactionPage(true);
    scanArmoryBalance();
    addFactionBalance();
    const after = queue().length;
    const added = Math.max(0, after - before);
    const details = [`${added} new event${added === 1 ? "" : "s"}`];
    if (armory.items) details.push(`${armory.items} ${armory.category} item types`);
    if (ocs) details.push(`${ocs} OC record${ocs === 1 ? "" : "s"}`);
    if (war) details.push("war report");
    if (syncToken() && syncApiKey()) {
      scheduleDirectSync(0);
      scannerToast(`Scan complete: ${details.join(" · ")}. Queue: ${after}. Live sync is sending and refreshing your balance.`);
      return;
    }
    const bridge = window.open(`${TREASURY_ORIGIN}/balance`, "blood-coven-balance-request", "popup=yes,width=520,height=740,resizable=yes,scrollbars=yes");
    scannerToast(`Scan complete: ${details.join(" · ")}. Queue: ${after}. ${bridge ? "Verify membership in the balance window once to enable background faction sync." : "Open the Blood Coven balance page and verify membership to enable background faction sync."}`, !bridge);
  }

  function ensureScannerButton() {
    if (document.getElementById("blood-coven-manual-scan")) return;
    const button = document.createElement("button");
    button.id = "blood-coven-manual-scan";
    button.type = "button";
    button.textContent = "BC ↻";
    button.title = "Drag to move. Click to scan this Torn page and synchronize usable faction data.";
    button.setAttribute("aria-label", "Scan Torn page for Blood Coven Treasury data");
    Object.assign(button.style, {
      position: "fixed", zIndex: "2147483646", width: "48px", height: "48px", borderRadius: "50%",
      border: "1px solid rgba(255,255,255,.45)", background: "#8e1b2d", color: "#fff", cursor: "grab",
      font: "800 11px/1 Arial,sans-serif", boxShadow: "0 4px 16px rgba(0,0,0,.4)", userSelect: "none", touchAction: "none",
    });
    const saved = GM_getValue(SCANNER_POSITION, null);
    const left = Number(saved?.left);
    const top = Number(saved?.top);
    button.style.left = `${Number.isFinite(left) ? Math.max(4, Math.min(window.innerWidth - 52, left)) : window.innerWidth - 66}px`;
    button.style.top = `${Number.isFinite(top) ? Math.max(4, Math.min(window.innerHeight - 52, top)) : Math.max(90, window.innerHeight - 150)}px`;

    let drag = null;
    button.addEventListener("pointerdown", (event) => {
      const box = button.getBoundingClientRect();
      drag = { startX: event.clientX, startY: event.clientY, left: box.left, top: box.top, moved: false };
      button.setPointerCapture(event.pointerId);
      button.style.cursor = "grabbing";
      event.preventDefault();
    });
    button.addEventListener("pointermove", (event) => {
      if (!drag) return;
      const dx = event.clientX - drag.startX;
      const dy = event.clientY - drag.startY;
      if (Math.abs(dx) + Math.abs(dy) > 5) drag.moved = true;
      const nextLeft = Math.max(4, Math.min(window.innerWidth - 52, drag.left + dx));
      const nextTop = Math.max(4, Math.min(window.innerHeight - 52, drag.top + dy));
      button.style.left = `${nextLeft}px`;
      button.style.top = `${nextTop}px`;
    });
    button.addEventListener("pointerup", (event) => {
      if (!drag) return;
      const moved = drag.moved;
      drag = null;
      button.releasePointerCapture(event.pointerId);
      button.style.cursor = "grab";
      GM_setValue(SCANNER_POSITION, { left: parseFloat(button.style.left), top: parseFloat(button.style.top) });
      if (!moved) manualScan();
    });
    document.body.appendChild(button);
  }

  if (location.origin === TREASURY_ORIGIN) {
    runTreasuryBridge();
    return;
  }

  ensureScannerButton();
  let scanTimer = 0;
  const scheduleScan = () => {
    window.clearTimeout(scanTimer);
    scanTimer = window.setTimeout(scanTorn, 800);
  };
  new MutationObserver(scheduleScan).observe(document.documentElement, { childList: true, subtree: true });
  scheduleScan();
  scheduleDirectSync(1200);
  window.setInterval(scanTorn, 30_000);
  window.setInterval(() => { void directSync(); }, 15_000);
})();