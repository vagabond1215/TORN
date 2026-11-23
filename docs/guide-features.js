"use strict";
// Torn City Guide API. Normally the key stays in memory; opt-in "Stay logged in" stores
// the key and a data snapshot in this browser only. Never store credentials in GitHub.
const tornGuideApi = (() => {
  let secret = null;
  let epoch = 0;
  let remember = false;
  let refreshTimer = null;
  let inFlight = null;
  const quarter = 15 * 60 * 1000;
  const authKey = "torn-city-guide:api:v2:remember";
  const cachePrefix = "torn-city-guide:api:v2:cache:";
  const state = { identity: null, data: {}, errors: {}, inventory: {}, inventoryErrors: {}, updated: null, loading: false, cached: false, storageWarning: null };
  function cachedKey(id) { return cachePrefix + id; }
  function announce() {
    if (typeof window !== "undefined" && typeof Event !== "undefined") window.dispatchEvent(new Event("torn-guide-sync"));
  }
  function clearSaved(id) {
    try {
      localStorage.removeItem(authKey);
      if(id!==null && id!==undefined) localStorage.removeItem(cachedKey(id));
    } catch { /* Browsers may disallow storage; current session still works. */ }
  }
  function saveOptIn() {
    if(!remember || !secret || !state.identity) return;
    try {
      const id=state.identity.id;
      localStorage.setItem(authKey,JSON.stringify({version:1,key:secret,identity:state.identity}));
      // Avoid serializing failed network requests or the API key as part of the profile data.
      const snapshot={version:1,playerId:id,updated:state.updated,data:state.data,inventory:state.inventory,errors:state.errors,inventoryErrors:state.inventoryErrors};
      localStorage.setItem(cachedKey(id),JSON.stringify(snapshot));
      state.storageWarning=null;
    } catch {
      state.storageWarning="Browser storage is unavailable or full; login and data may not persist.";
      remember=false;
      clearSaved(state.identity.id);
    }
  }
  function isRemembering(){return remember;}
  function setRemember(enabled){
    if(!secret || !state.identity) return false;
    if(!enabled){remember=false;clearSaved(state.identity.id);state.cached=false;state.storageWarning=null;announce();return false;}
    remember=true;saveOptIn();announce();return remember;
  }
  function restore(){
    let record;
    try { record=JSON.parse(localStorage.getItem(authKey)||"null"); } catch {return null;}
    const identity=record && record.identity;
    if(!record || !/^[a-zA-Z0-9]{16}$/.test(String(record.key||"")) || !identity ||
      !Number.isInteger(Number(identity.id)) || !identity.name) {clearSaved(identity&&identity.id);return null;}
    secret=record.key;remember=true;epoch++;
    state.identity={id:Number(identity.id),name:String(identity.name),level:identity.level};
    state.data={};state.inventory={};state.errors={};state.inventoryErrors={};
    state.updated=null;state.cached=false;state.storageWarning=null;
    try{
      const snap=JSON.parse(localStorage.getItem(cachedKey(state.identity.id))||"null");
      if(snap && snap.version===1 && Number(snap.playerId)===state.identity.id){
        state.data=snap.data&&typeof snap.data==="object"?snap.data:{};
        state.inventory=snap.inventory&&typeof snap.inventory==="object"?snap.inventory:{};
        state.errors=snap.errors&&typeof snap.errors==="object"?snap.errors:{};
        state.inventoryErrors=snap.inventoryErrors&&typeof snap.inventoryErrors==="object"?snap.inventoryErrors:{};
        state.updated=Number.isFinite(Number(snap.updated))?Number(snap.updated):null;
        state.cached=true;
      }
    }catch { /* Corrupted cache is ignored; credentials remain reusable. */ }
    scheduleRefresh();
    announce();
    return {identity:state.identity,cached:state.cached,updated:state.updated};
  }
  function stopRefreshTimer(){
    if(refreshTimer!==null){clearTimeout(refreshTimer);refreshTimer=null;}
  }
  function scheduleRefresh(){
    stopRefreshTimer();
    if(!secret)return;
    const now=Date.now();
    const next=(Math.floor(now/quarter)+1)*quarter;
    refreshTimer=setTimeout(async()=>{
      refreshTimer=null;
      if(secret){
        try{await refresh();}catch(error){state.storageWarning="Automatic refresh failed: "+String(error.message||error);announce();}
        scheduleRefresh();
      }
    },Math.max(200,next-now+150));
  }
  function refreshOnResume(){
    if(!secret || (typeof document!=="undefined" && document.visibilityState==="hidden"))return;
    if(!state.updated || Date.now()-state.updated>=quarter){
      refresh().catch(error=>{state.storageWarning="Refresh failed: "+String(error.message||error);announce();});
    }
    scheduleRefresh();
  }
  if(typeof document!=="undefined")document.addEventListener("visibilitychange",()=>{if(document.visibilityState==="visible")refreshOnResume();});
  if(typeof window!=="undefined")window.addEventListener("focus",refreshOnResume);
  const inventoryTypes = ["Candy", "Drug", "Alcohol", "Tool", "Enhancer", "Booster", "Energy Drink", "Medical"];
  async function request(path, candidate) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 15000);
    try {
      const response = await fetch("https://api.torn.com/v2/" + path, {
        method: "GET", headers: { "Authorization": "ApiKey " + candidate, "Accept": "application/json" },
        cache: "no-store", credentials: "omit", referrerPolicy: "no-referrer", signal: controller.signal
      });
      const payload = await response.json();
      if (payload && payload.error) throw Error("Torn API: " + String(payload.error.error || payload.error.message || payload.error.code || "request rejected"));
      if (!response.ok) throw Error("Torn API HTTP " + response.status);
      return payload;
    } catch (error) {
      if (error instanceof TypeError) throw Error("Could not reach Torn API. Check connectivity and browser CORS permissions; no third-party proxy is used.");
      if (error.name === "AbortError") throw Error("Torn API request timed out.");
      throw error;
    } finally { clearTimeout(timeout); }
  }
  async function connect(raw, stay = false) {
    const candidate = String(raw || "").trim();
    if (!/^[a-zA-Z0-9]{16}$/.test(candidate)) throw Error("Enter a valid 16-character Torn API key.");
    const rawBasic = await request("user/basic", candidate);
    const person = rawBasic.profile;
    if (!person || !Number.isInteger(person.id) || !person.name) throw Error("Torn returned an unexpected profile response.");
    if(remember)clearSaved(state.identity && state.identity.id);
    secret = candidate; epoch += 1;
    state.identity = { id: person.id, name: person.name, level: person.level };
    state.data = { basic: rawBasic }; state.errors = {}; state.inventory = {}; state.inventoryErrors = {}; state.updated = null;state.cached=false;state.storageWarning=null;
    remember=Boolean(stay);
    if(remember)saveOptIn();
    scheduleRefresh();
    announce();
    return state.identity;
  }
  async function refreshInternal() {
    if (!secret) throw Error("Connect a Torn API key first.");
    const currentEpoch = ++epoch;
    state.loading = true;
    state.storageWarning=null;
    announce();
    const endpointNames = ["bars", "battlestats", "gym", "perks", "profile", "property", "job", "education", "merits", "honors", "money", "stocks", "workstats", "cooldowns", "equipment", "personalstats"];
    const work = [
      ...endpointNames.map(async name => {
        try { return { name, value: await request("user/" + name, secret) }; }
        catch (err) { return { name, error: String(err.message || err) }; }
      }),
      (async () => {
        try { return { name: "meritCatalog", value: await request("torn/merits", secret) }; }
        catch (err) { return { name: "meritCatalog", error: String(err.message || err) }; }
      })(),
      (async () => {
        try { return { name: "stockCatalog", value: await request("torn/stocks", secret) }; }
        catch (err) { return { name: "stockCatalog", error: String(err.message || err) }; }
      })(),
      (async () => {
        try { return { name: "gymCatalog", value: await request("torn/gyms", secret) }; }
        catch (err) { return { name: "gymCatalog", error: String(err.message || err) }; }
      })(),
      ...inventoryTypes.map(async category => {
        try {
          const gathered = [];
          let total = null;
          for (let offset = 0; offset < 2500; offset += 250) {
            const payload = await request("user/inventory?cat=" + encodeURIComponent(category) + "&limit=250&offset=" + offset, secret);
            const batch = payload.inventory && Array.isArray(payload.inventory.items) ? payload.inventory.items : [];
            gathered.push(...batch);
            total = Number(payload._metadata && payload._metadata.total);
            if (batch.length < 250 || (Number.isFinite(total) && total >= 0 && gathered.length >= total)) break;
          }
          return { category, value: gathered, truncated: total > gathered.length };
        } catch (err) { return { category, error: String(err.message || err) }; }
      })
    ];
    const results = await Promise.all(work);
    if (currentEpoch !== epoch || !secret) return;
    let succeeded = 0;
    for (const result of results) {
      if (result.category) {
        if (result.error) state.inventoryErrors[result.category] = result.error;
        else { state.inventory[result.category] = result.value; delete state.inventoryErrors[result.category]; succeeded++; }
        if (result.truncated) state.inventoryErrors[result.category] = "List capped at 2,500 items.";
      } else if (result.error) state.errors[result.name] = result.error;
      else { state.data[result.name] = result.value; delete state.errors[result.name]; succeeded++; }
    }
    if(succeeded){
      state.updated = Date.now();
      state.cached = false;
    }
    state.loading = false;
    saveOptIn();
    if(!succeeded)state.storageWarning="No Torn API sections refreshed successfully; showing the last available snapshot.";
    announce();
    if (["","#home","#dashboard","#quickstart","#checklist","#stats"].includes(location.hash)) renderRoute();
    else if(location.hash==="#crime" && typeof tornCrimeGuide!=="undefined") tornCrimeGuide.syncNerve();
    return { failures: Object.keys(state.errors).length + Object.keys(state.inventoryErrors).length };
  }
  function refresh(){
    if(!secret)return Promise.reject(Error("Connect a Torn API key first."));
    if(inFlight)return inFlight;
    inFlight=refreshInternal().finally(()=>{inFlight=null;state.loading=false;announce();});
    return inFlight;
  }
  function disconnect() {
    const id=state.identity && state.identity.id;
    epoch += 1; secret = null; remember=false;
    stopRefreshTimer();
    clearSaved(id);
    state.identity = null; state.data = {}; state.errors = {};
    state.inventory = {}; state.inventoryErrors = {}; state.updated = null; state.loading = false;
    state.cached=false;state.storageWarning=null;
    announce();
  }
  return { state, connect, refresh, disconnect, restore, setRemember, isRemembering, refreshOnResume,
    isConnected: () => Boolean(secret) };
})();

const guideSteps = [
  { id:"tutorial", stage:"First hour", title:"Finish the tutorial and learn the bars", detail:"Energy is for training/attacking; nerve is for Crimes 2.0. Avoid sitting at full bars.", source:"https://wiki.torn.com/wiki/New_Player_Missions" },
  { id:"first-merit", stage:"First hour", title:"Earn an easy early honor and merit", detail:"Check the Awards page for inexpensive honors such as Historian, Gone Fishing, Landlord and Pocket Money. Confirm each requirement in-game before spending.", source:"https://wiki.torn.com/wiki/Award" },
  { id:"education-start", stage:"First hour", title:"Start an education course immediately", detail:"Begin a useful course and keep one running. Consider Introduction to Biochemistry and work toward Intravenous Therapy, then Sports Science.", source:"https://wiki.torn.com/wiki/Education" },
  { id:"education-merit", stage:"First hour", title:"Invest merits into Education Length, ultimately 10/10", detail:"Each upgrade saves 2% on FUTURE courses; 10/10 grants 20% total. Fully upgrading costs 55 merits, so this is a long-term target.", source:"https://wiki.torn.com/wiki/Education", auto:"educationMerit" },
  { id:"first-job", stage:"First hour", title:"Get a job or start applying to companies", detail:"Use a starter city job while applying to player companies. Compare work-stat training and company specials; a useful company may beat starter-job cash.", source:"https://wiki.torn.com/wiki/Job", auto:"job" },
  { id:"faction", stage:"First hour", title:"Join an active, beginner-friendly faction", detail:"Ask about training bonuses, armory, protection, organized crimes, missions, and war expectations.", source:"https://wiki.torn.com/wiki/Faction" },
  { id:"first-property", stage:"First week", title:"Move beyond the starter Shack", detail:"An Apartment costs $25k (125 base Happy), but renting a Mansion (500 base Happy) can be better value if affordable. Compare current listings, upkeep and rental terms.", source:"https://wiki.torn.com/wiki/Property" },
  { id:"daily-training", stage:"First week", title:"Use gym energy consistently", detail:"Higher Happy improves gains. Track Strength, Defense, Speed and Dexterity. Avoid wasting energy by keeping it capped.", source:"https://wiki.torn.com/wiki/Gym" },
  { id:"candy", stage:"First week", title:"Learn candy, happy and booster cooldowns", detail:"Candy can increase Happy before gym training. Check booster cooldown and Torn-time Happy resets; never blindly copy expensive jump routines.", source:"https://wiki.torn.com/wiki/Happy" },
  { id:"starter-crimes", stage:"First week", title:"Build Crime Experience with easier crimes", detail:"Start with Search for Cash or Bootlegging and advance when reliable. Shoplifting, Pickpocketing, Burglary and Hustling offer different money/XP tradeoffs. Consistent success matters more than rushing difficult crimes.", source:"https://wiki.torn.com/wiki/Crimes" },
  { id:"starter-cash", stage:"First week", title:"Establish non-crime income", detail:"Check city finds, resell eligible city-shop goods after market-fee math, and compare item-market demand. Cash from crimes alone is not usually the fastest route to travel funding.", source:"https://www.torn.com/forums.php?p=threads&t=16607164" },
  { id:"honors", stage:"First week", title:"Collect inexpensive honors strategically", detail:"Look up requirements for Pocket Money (first bank deposit), Historian, Landlord and early activity honors. Avoid spending more on an honor than the reward is worth.", source:"https://wiki.torn.com/wiki/Award" },
  { id:"missions", stage:"First week", title:"Check Duke missions and daily routines", detail:"Missions, education, faction participation, crime and training should become a regular rhythm.", source:"https://wiki.torn.com/wiki/Mission" },
  { id:"bank", stage:"First week", title:"Begin bank investments and obtain Pocket Money", detail:"Bank deposits safely earn interest but lock funds for the selected term. New players unlock longer terms progressively.", source:"https://wiki.torn.com/wiki/Bank" },
  { id:"level15", stage:"Level 15", title:"Reach level 15 and unlock travel", detail:"Train enough to attack appropriate leveling targets. Avoid random stronger targets. Level 15 unlocks international travel and major trade income.", source:"https://www.torn.com/forums.php?p=threads&t=16582732", auto:"level15" },
  { id:"travel", stage:"Level 15", title:"Learn profitable flower/plushie travel loops", detail:"Compare local buying prices, Torn sell prices, time away and mugging risk. Travel light and avoid carrying unnecessary money.", source:"https://wiki.torn.com/wiki/Travel" },
  { id:"stock-ticker", stage:"Level 15", title:"Buy the Stock Ticker at the Points Building", detail:"The Stock Ticker costs 50 points, unlocking the stock market. Check point prices and avoid sacrificing essential early progress.", source:"https://wiki.torn.com/wiki/Stock_Market" },
  { id:"suitcase", stage:"Level 15", title:"Acquire a Large Suitcase when it pays for itself", detail:"A Large Suitcase currently adds +3 travel-item capacity (since the June 2026 change); suitcases do not stack. At the Hawaii shop it costs $10m.", source:"https://wiki.torn.com/wiki/Large_Suitcase", auto:"suitcase" },
  { id:"pi-rent", stage:"Level 15", title:"Plan a Private Island rental", detail:"Renting a Private Island is a realistic path to higher Happy and a faster-travel pilot before buying a PI; verify pilot/upkeep terms.", source:"https://wiki.torn.com/wiki/Property" },
  { id:"bank-merit", stage:"Long-term", title:"Raise Bank Interest to 10/10 as deposits grow", detail:"Each merit upgrade increases bank APR by 5%; prioritize it when investment principal makes the gain meaningful. A complete line costs 55 merits.", source:"https://wiki.torn.com/wiki/Bank", auto:"bankMerit" },
  { id:"wsu", stage:"Long-term", title:"Acquire the WSU education stock benefit", detail:"Hold 1,000,000 West Side University shares for a passive 10% reduction to FUTURE education course lengths; monitor current price.", source:"https://wiki.torn.com/wiki/Education", auto:"wsu" },
  { id:"principal", stage:"Long-term", title:"Obtain the permanent Principal education-job perk", detail:"Reaching Principal in the Education starter career grants a permanent 10% education-time reduction, even after leaving.", source:"https://wiki.torn.com/wiki/Education" },
  { id:"crime-progression", stage:"Long-term", title:"Invest in Crime Progression when useful", detail:"Crimes 2.0 progression merits improve crime experience and skill gains. Avoid repeatedly failing harder crimes.", source:"https://wiki.torn.com/wiki/Crimes" },
  { id:"bank-2b", stage:"Long-term", title:"Build a sustainable bank investment fund", detail:"The ordinary bank investment cap is $2 billion; invest within your cash-flow needs and grow toward it over time.", source:"https://wiki.torn.com/wiki/Bank" },
  { id:"pi-buy", stage:"Long-term", title:"Eventually purchase a Private Island", detail:"A PI costs $500 million base before extensive upgrades. Treat purchase as a major wealth milestone, not a beginner requirement.", source:"https://wiki.torn.com/wiki/Property" },
  { id:"routine", stage:"Ongoing", title:"Keep an efficient daily schedule", detail:"Check bars, cooldowns, active education, faction activity, crimes, training, missions and available inventory before spending.", source:"https://wiki.torn.com/wiki/Main_Page" }
];
function safe(value) {
  return String(value == null ? "" : value).replace(/[&<>"']/g, character => ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[character]));
}
function sourceError(name) { return tornGuideApi.state.errors[name] ? '<p class="api-error">' + safe(name + ": " + tornGuideApi.state.errors[name]) + '</p>' : ""; }
function payload(name, field) {
  const item = tornGuideApi.state.data[name];
  return item ? (field && item[field] !== undefined ? item[field] : item) : null;
}
function formatNumber(value) {
  const number = Number(value);
  return value === null || value === undefined || !Number.isFinite(number) ? "Not available" : number.toLocaleString();
}
function meritLevel(name) {
  const user = payload("merits", "merits");
  const catalog = payload("meritCatalog", "merits");
  if (!user || !Array.isArray(user.upgrades) || !Array.isArray(catalog)) return null;
  const definition = catalog.find(merit => String(merit.name).toLowerCase() === name.toLowerCase());
  if (!definition) return null;
  const upgrade = user.upgrades.find(entry => Number(entry.id) === Number(definition.id));
  return upgrade ? Number(upgrade.level) : 0;
}
function ownedStockPositions() {
  const holdings = payload("stocks", "stocks");
  const catalog = payload("stockCatalog", "stocks");
  if (!Array.isArray(holdings) || !Array.isArray(catalog)) return null;
  return holdings.map(item => ({
    ...item,
    details: catalog.find(stock => Number(stock.id) === Number(item.id)) || null
  }));
}
function heldWsuShares() {
  const positions = ownedStockPositions();
  if (!positions) return null;
  const position = positions.find(item => item.details &&
    (String(item.details.acronym).toUpperCase() === "WSU" ||
    String(item.details.name).toLowerCase() === "west side university"));
  return position ? Number(position.shares || 0) : 0;
}
function autoDone(step) {
  const st = tornGuideApi.state;
  if (!st.identity) return false;
  if (step.auto === "level15") return Number(st.identity.level) >= 15;
  if (step.auto === "educationMerit") return meritLevel("Education Length") === 10;
  if (step.auto === "bankMerit") return meritLevel("Bank Interest") === 10;
  if (step.auto === "wsu") return heldWsuShares() !== null && heldWsuShares() >= 1000000;
  if (step.auto === "suitcase") return (st.inventory.Enhancer || []).some(item => item.name === "Large Suitcase" && Number(item.amount) > 0);
  if (step.auto === "job") {
    const info = payload("job", "job");
    return Boolean(info && typeof info === "object" && (info.name || info.position || info.company_name));
  }
  return false;
}
function stepKey(id) { return activeProfile ? activeKey("quickstart:" + id) : "quickstart:guest:" + id; }
function renderQuickstart() {
  const sections = [...new Set(guideSteps.map(step => step.stage))];
  const count = guideSteps.filter(step => autoDone(step) || read(stepKey(step.id)) === "done").length;
  let output = '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Checklist & quickstart</h1><p>Your daily routine and milestone roadmap are now one checklist. Supported milestones are checked against your Torn API data; your previous progress remains saved.</p></header>';
  output += '<section class="panel"><div class="panel-heading"><h2>Daily routine</h2></div><div class="panel-content"><p id="task-progress" role="status"></p><div class="checklist">' + Object.entries(tasks).map(([id,label]) => '<label><input type="checkbox" name="' + safe(id) + '" ' + (activeProfile ? "" : "disabled") + '><span>' + safe(label) + '</span></label>').join("") + '</div><p class="fine-print">The daily tasks reuse your old Checklist progress. Uncheck these when starting a new day.</p></div></section>';
  output += '<div class="panel"><div class="panel-content"><p class="progress-line" role="status">' + count + " of " + guideSteps.length + ' milestones complete</p><p class="fine-print">Guidance last reviewed November 2026. Rental prices and game mechanics may change. Always verify current in-game prices.</p></div></div>';
  for (const stage of sections) {
    output += '<section class="panel"><div class="panel-heading"><h2>' + safe(stage) + '</h2></div><div class="panel-content step-list">';
    for (const step of guideSteps.filter(item => item.stage === stage)) {
      const verified = autoDone(step);
      const checked = verified || read(stepKey(step.id)) === "done";
      output += '<div class="step-row"><label><input class="milestone-check" type="checkbox" data-step="' + safe(step.id) + '" ' + (checked ? "checked " : "") + (verified ? "disabled " : "") + '><span><strong>' + safe(step.title) + '</strong><small>' + safe(step.detail) + '</small></span></label><div class="step-foot">' + (verified ? '<span class="verified">Verified by API</span>' : "") + '<a href="' + safe(step.source) + '" target="_blank" rel="noopener noreferrer">Reference ↗</a></div></div>';
    }
    output += "</div></section>";
  }
  return output;
}
function wireQuickstart() {
  for (const checkbox of document.querySelectorAll(".milestone-check")) {
    checkbox.addEventListener("change", () => {
      write(stepKey(checkbox.dataset.step), checkbox.checked ? "done" : null);
      const count = guideSteps.filter(step => autoDone(step) || read(stepKey(step.id)) === "done").length;
      document.querySelector(".progress-line").textContent = count + " of " + guideSteps.length + " milestones complete";
    });
  }
}
function metric(label, value, description) {
  return '<div class="metric"><span class="metric-label">' + safe(label) + '</span><strong class="metric-value">' + safe(value) + '</strong>' + (description ? '<small>' + safe(description) + '</small>' : "") + "</div>";
}
function val(obj, key) { return obj && typeof obj === "object" ? obj[key] : undefined; }
function barsMarkup() {
  const bars = payload("bars", "bars");
  if (!bars) return sourceError("bars") || '<p>Bars not loaded yet.</p>';
  return '<div class="metric-grid">' + ["energy", "nerve", "happy", "life"].map(name => {
    const b = bars[name];
    return metric(name[0].toUpperCase() + name.slice(1), (b && b.current !== undefined ? formatNumber(b.current) : "?") + " / " + (b && b.maximum !== undefined ? formatNumber(b.maximum) : "?"));
  }).join("") + "</div>";
}
function battleMarkup() {
  const stats = payload("battlestats", "battlestats");
  if (!stats) return sourceError("battlestats") || '<p>Battle stats not loaded yet.</p>';
  return '<div class="metric-grid">' + ["strength", "defense", "speed", "dexterity", "total"].map(name => metric(name[0].toUpperCase() + name.slice(1), formatNumber(stats[name] && typeof stats[name] === "object" ? stats[name].value : stats[name]))).join("") + "</div>";
}
function inventoryMarkup() {
  let result = '<p class="fine-print">Torn caches inventory by category for 15 minutes. Quantities reflect the last successful API response. Sections show your inventory, not the faction armory.</p><div class="inventory-grid">';
  for (const category of ["Candy", "Drug", "Alcohol", "Tool", "Enhancer", "Booster", "Energy Drink", "Medical"]) {
    const list = tornGuideApi.state.inventory[category];
    const error = tornGuideApi.state.inventoryErrors[category];
    result += '<section class="inventory-panel"><h3>' + safe(category) + (list ? " (" + list.length + ")" : "") + '</h3>';
    if (error) result += '<p class="api-error">' + safe(error) + "</p>";
    else if (!list) result += '<p>Not loaded yet.</p>';
    else if (list.length === 0) result += '<p>Nothing currently held.</p>';
    else result += '<ul class="item-list">' + list.map(item => '<li><span>' + safe(item.name) + (item.equipped ? ' <small>(equipped)</small>' : "") + '</span><strong>×' + safe(formatNumber(item.amount)) + '</strong></li>').join("") + '</ul>';
    result += "</section>";
  }
  result += "</div>";
  return result;
}
function renderDashboard() {
  let result = '<header class="panel topic-header"><h1 id="topic-title" tabindex="-1">Live character dashboard</h1><p>Private read-only snapshots directly from Torn API v2. Full Access keys are accepted; most displayed selections work with a more restrictive key.</p></header>';
  if (!tornGuideApi.isConnected()) return result + '<section class="panel"><div class="panel-content"><p>Connect your own Torn API key in <a href="#profile">Account</a> to populate this dashboard. No key is stored in the browser.</p></div></section>';
  const st = tornGuideApi.state;
  result += '<div class="panel"><div class="panel-content"><p class="progress-line">' + safe(st.identity.name) + " [#" + safe(st.identity.id) + "] · Level " + safe(st.identity.level) + '</p><p class="fine-print">' + (st.loading ? "Refreshing…" : st.updated ? "Last refreshed: " + safe(new Date(st.updated).toLocaleString()) + (st.cached ? " (restored from browser cache)" : " (live Torn API)") : "Connecting…") + '</p></div></div>';
  const cooldown=payload("cooldowns","cooldowns");
  const cdText=value=>{
    if(value===null||value===undefined||!Number.isFinite(Number(value)))return "Not available";
    const seconds=Math.max(0,Math.ceil(Number(value)));
    if(seconds<=0)return "Ready";
    return Math.floor(seconds/3600)+"h "+Math.floor(seconds%3600/60)+"m";
  };
  result += '<section class="panel"><div class="panel-heading"><h2>Cooldowns and next actions</h2></div><div class="panel-content">';
  result += '<div class="metric-grid">'+
    metric("Drug cooldown",cooldown?cdText(cooldown.drug):"Unavailable")+
    metric("Booster cooldown",cooldown?cdText(cooldown.booster):"Unavailable")+
    metric("Medical cooldown",cooldown?cdText(cooldown.medical):"Unavailable")+
    metric("Education",payload("education","education")&&payload("education","education").current?"Course in progress":"Check courses")+
    '</div>';
  result += sourceError("cooldowns") + '<p class="fine-print">Timers show your last API snapshot, not a running countdown. <a href="#stats">Plan a gym session</a> or <a href="#checklist">review your checklist</a>.</p></div></section>';
  result += '<section class="panel"><div class="panel-heading"><h2>Energy, nerve, happiness and life</h2></div><div class="panel-content">' + barsMarkup() + '</div></section>';
  result += '<section class="panel"><div class="panel-heading"><h2>Battle stats</h2></div><div class="panel-content">' + battleMarkup() + '</div></section>';
  const gym = payload("gym", "gym");
  const merits = payload("merits", "merits");
  const job = payload("job", "job");
  const property = payload("property", "property");
  const cash = payload("money", "money");
  const education = payload("education", "education");
  result += '<section class="panel"><div class="panel-heading"><h2>Gym, career and property</h2></div><div class="panel-content"><div class="metric-grid">';
  result += metric("Current gym", gym && gym.name || "Not available", gym && Array.isArray(gym.unlocked_gyms) ? gym.unlocked_gyms.filter(g => g.available).length + " gyms available" : "");
  result += metric("Job", job && (job.name || job.position || job.company_name) || "Not available");
  result += metric("Property", property && (property.name || (property.property && property.property.name)) || "Not available");
  result += metric("Cash on hand", cash && cash.wallet !== undefined ? "$" + formatNumber(cash.wallet) : "Not available");
  result += metric("Bank balance", cash && cash.city_bank && cash.city_bank.amount !== undefined ? "$" + formatNumber(cash.city_bank.amount) : cash ? "No active deposit" : "Not available");
  result += metric("Points", cash && cash.points !== undefined ? formatNumber(cash.points) : "Not available");
  result += '</div>';
  if (gym && Array.isArray(gym.unlocked_gyms)) {
    result += '<h3 class="subheading">Gym access</h3><ul class="gym-list">' +
      gym.unlocked_gyms.map(item => '<li>' + safe(item.name) + ' <small>' +
        (item.available ? "Available" : "Not yet available") + '</small></li>').join("") + '</ul>';
  }
  result += ["gym", "job", "property", "money"].map(sourceError).join("") + '</div></section>';
  result += '<section class="panel"><div class="panel-heading"><h2>Education and merits</h2></div><div class="panel-content"><div class="metric-grid">';
  result += metric("Education Length", meritLevel("Education Length") === null ? "Not available" : meritLevel("Education Length") + " / 10");
  result += metric("Bank Interest", meritLevel("Bank Interest") === null ? "Not available" : meritLevel("Bank Interest") + " / 10");
  result += metric("Available merits", merits ? formatNumber(merits.available) : "Not available");
  result += metric("Completed courses", education && Array.isArray(education.complete) ? formatNumber(education.complete.length) : "Not available");
  result += metric("Current course", education ? (education.current ? "Course #" + education.current.id : "None active") : "Not available");
  result += metric("Honors earned", merits && merits.honors !== undefined ? formatNumber(merits.honors) : "Not available");
  result += '</div>' + ["education", "merits", "meritCatalog"].map(sourceError).join("") + '</div></section>';
  const stockPositions = ownedStockPositions();
  result += '<section class="panel"><div class="panel-heading"><h2>Stock holdings and education benefit</h2></div><div class="panel-content"><div class="metric-grid">';
  const wsuShares = heldWsuShares();
  result += metric("WSU shares", wsuShares === null ? "Not available" : formatNumber(wsuShares), wsuShares !== null && wsuShares >= 1000000 ? "Education block unlocked" : "Goal: 1,000,000 shares");
  result += metric("Stock positions", stockPositions ? formatNumber(stockPositions.length) : "Not available");
  result += '</div>';
  if (stockPositions && stockPositions.length) {
    result += '<ul class="item-list stock-list">' + stockPositions.map(item =>
      '<li><span>' + safe(item.details && (item.details.name || item.details.acronym) || "Stock #" + item.id) +
      '</span><strong>' + safe(formatNumber(item.shares)) + ' shares</strong></li>').join("") + '</ul>';
  }
  result += sourceError("stocks") + sourceError("stockCatalog") + '</div></section>';
  result += '<section class="panel"><div class="panel-heading"><h2>Your inventory</h2></div><div class="panel-content">' + inventoryMarkup() + '</div></section>';
  result += '<section class="panel"><div class="panel-heading"><h2>Activity and detailed reports</h2></div><div class="panel-content"><p class="fine-print">Torn Report has deeper histories and charts than the API snapshot shown here. These links open your existing Torn Report account; this guide does not access or copy its private logs.</p><div class="report-links">';
  for(const [label,url,tip] of [
    ["Energy","https://torn.report/energy","Energy use & recovery"],
    ["Nerve","https://torn.report/nerve","Crime nerve history"],
    ["Education","https://torn.report/education","Courses and education benefits"],
    ["Drugs","https://torn.report/drugs","Drug use history"],
    ["Racing","https://torn.report/racing","Races and performance"],
    ["Crime uniques","https://torn.report/uniques","Unique crime outcomes"],
    ["Trains received","https://torn.report/trains","Workplace training history"],
    ["Organized crimes","https://torn.report/oc","Faction crime participation"],
    ["Travel","https://torn.report/travel","Travel activity and trips"]
  ]){
    result += '<a href="'+safe(url)+'" target="_blank" rel="noopener noreferrer"><strong>'+safe(label)+'</strong><small>'+safe(tip)+'</small></a>';
  }
  result += '</div></div></section>';
  const errors = Object.keys(st.errors).length + Object.keys(st.inventoryErrors).length;
  if(errors){
    result += '<section class="panel"><div class="panel-heading"><h2>API diagnostics (' + errors + ' unavailable)</h2></div><div class="panel-content"><p class="fine-print">A Full Access key does not resolve invalid endpoints, cache limits or temporary API failures. Here are the specific requests that need attention.</p><ul class="api-failure-list">';
    for(const [name,reason] of Object.entries(st.errors)){
      const path=name==="gymCatalog"?"torn/gyms":name==="meritCatalog"?"torn/merits":name==="stockCatalog"?"torn/stocks":"user/"+name;
      result += '<li><strong>/v2/' + safe(path) + '</strong><small>' + safe(reason) + '</small></li>';
    }
    for(const [category,reason] of Object.entries(st.inventoryErrors)) result += '<li><strong>Inventory: '+safe(category)+'</strong><small>'+safe(reason)+'</small></li>';
    result += '</ul></div></section>';
  }
  return result;
}

