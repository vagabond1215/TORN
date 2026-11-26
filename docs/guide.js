"use strict";

const topics = {
  calendar:{title:"Calendar",summary:"Training, rehab and faction schedule",intro:"Shared activity schedule in Torn City Time."},
  log:{title:"Log",summary:"Personal activity history",intro:"Browse locally captured Torn activity entries."},
  checklist: {
    title: "Checklist",
    summary: "Milestones and daily routine",
    intro: "Your beginner roadmap and daily tasks in one checklist.",
  },
  stats: {
    title: "Stats",
    summary: "Four-stat calculator and happy-jump comparator",
    intro: "Calculate gym gains, track perks, and compare natural energy with happy jumps.",
    prompts: ["Record a baseline for your four battle stats.", "Pick one short-term training goal.", "Set a date to compare your progress."],
  },
  inventory: { title: "Inventory", summary: "Load only the categories you need", intro: "On-demand inventory, with per-category caching." },
  merits: { title: "Merits", summary: "Honors, medals and merit progression", intro: "Find attainable awards." },
  education: { title: "Education", summary: "Courses and progress", intro: "Review your education progress and available courses." },
  stocks: { title: "Stocks", summary: "Stock holdings and benefits", intro: "Review your stock portfolio and benefit blocks." },
  faction: {
    title: "Faction",
    summary: "Find your place in a crew",
    intro: "Use this page to compare factions and remember what your crew expects from you.",
    prompts: ["Ask about activity requirements and war schedules.", "Check how armory access and payouts work.", "Write down who to contact for help."],
  },
  jobs: { title: "Jobs", summary: "City careers and all 39 companies", intro: "Find training, permanent passives and player-owned job perks." },
  racing: { title: "Racing", summary: "Tracks, cars, upgrades and point saving", intro: "Reach Class A with points saved for a competitive car." },
  crime: {
    title: "Crime",
    summary: "Crimes 2.0, CE, NNB and difficulty",
    intro: "Build crime experience and tackle harder crimes safely.",
    prompts: ["Check your available nerve before starting.", "Review the requirements shown in the game.", "Record any outcomes you want to compare later."],
  },
  attacking: {
    title: "Attacking",
    summary: "Prepare for in-game fights",
    intro: "Review your loadout and decide what you want to achieve before spending energy on a fight in Torn.",
    prompts: ["Check your equipment and available energy.", "Decide whether the fight serves a mission, chain, or war goal.", "Review your attack log to see what you can improve."],
  },
  war: {
    title: "War",
    summary: "Get ready for faction wars",
    intro: "Keep your faction’s war schedule, priorities, and instructions in one place.",
    prompts: ["Confirm the start time and your availability.", "Review your faction’s targeting and chain instructions.", "Check which supplies your faction will provide."],
  },
  money: {
    title: "Money",
    summary: "Track income and costs",
    intro: "Keep track of where your Torn dollars come from and what you’re saving for.",
    prompts: ["List your regular income sources.", "Include fees and purchase costs when comparing profits.", "Set aside a budget for training and faction costs."],
  },
  tools: {
    title: "Tools",
    summary: "Desktop, phone and tablet tools",
    intro: "Choose useful Torn tools for your device and gameplay style.",
    prompts: ["Save links to your preferred Torn resources.", "Write down what each tool helps you track.", "Keep API keys and other secrets out of your notes."],
  },
};

const icons = {
  log: '<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h8M8 11h8M8 15h5M8 18h3"/>',
  calendar: '<rect x="3" y="5" width="18" height="16" rx="2"/><path d="M7 3v4m10-4v4M3 10h18M7 14h2m3 0h2m3 0h1M7 17h2m3 0h2"/>',
  merits: '<circle cx="12" cy="8" r="5"/><path d="m8 12-2 10 6-4 6 4-2-10"/>',
  education: '<path d="m2 9 10-5 10 5-10 5zM6 11v6c4 3 8 3 12 0v-6M22 9v7"/>',
  stocks: '<path d="M3 3v18h18M5 15l5-5 4 3 7-8M16 5h5v5"/>',
  dashboard: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 10h18M10 10v11"/>',
  quickstart: '<path d="M4 12l5 5L20 6"/><path d="M4 4h16v16H4z"/>',
  home: '<path d="m3 10 9-7 9 7v10H3z"/><path d="M9 20v-7h6v7"/>',
  checklist: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V2h6v2m-7 8 2 2 5-5m-6 8h6"/>',
  faction: '<path d="M12 22s7-3 7-10V5l-7-3-7 3v7c0 7 7 10 7 10Z"/><path d="M12 8v7m-3-4h6"/>',
  stats: '<path d="M3 3v18h18M7 17v-5m5 5V8m5 9V5"/>',
  jobs: '<rect x="4" y="7" width="16" height="14" rx="2"/><path d="M9 7V4h6v3m-11 7h16"/>',
  racing: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4"/><path d="m12 12 4-7"/>',
  crime: '<path d="M3 11c0-4 4-7 9-7s9 3 9 7-4 8-9 8-9-4-9-8Z"/><circle cx="8" cy="11" r="2"/><circle cx="16" cy="11" r="2"/>',
  attacking: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>',
  war: '<path d="m4 4 5 1 10 10-4 4L5 9zM20 4l-5 1-3 3m-4 4-3 3 4 4 3-3m1 5 8-8M3 13l8 8"/>',
  inventory: '<rect x="3" y="5" width="18" height="15" rx="2"/><path d="M3 10h18M8 14h8"/>',
  money: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12h1m10 0h1"/>',
  tools: '<path d="M14 6a4 4 0 0 0-5 5L3 17a2 2 0 0 0 4 4l6-6a4 4 0 0 0 5-5l-3 3-4-4z"/>',
};

const tasks = {
  energy: "Decide how to spend your energy",
  nerve: "Check your nerve and plan a crime",
  faction: "Check faction messages and plans",
  money: "Review your cash and savings goal",
  education: "Confirm a current course is underway",
  cooldowns: "Review drug, booster and medical cooldowns",
  city: "Check City finds, missions, and travel timing",
};

const byId = (id) => document.getElementById(id);
const prefix = "torn-city-guide:v1:";
const temporaryStorage = new Map();
let persistent = true;
let activeProfile = null;
let activePlayerName = "";
let lastRoute;

function markStorageUnavailable() {
  persistent = false;
  const message = byId("storage-message");
  message.textContent = "Browser storage is unavailable. Changes made now last until you close or reload this page.";
  message.hidden = false;
}

function read(key) {
  if (persistent) {
    try {
      const value = localStorage.getItem(prefix + key);
      if (value === null) temporaryStorage.delete(key);
      else temporaryStorage.set(key, value);
      return value;
    } catch {
      markStorageUnavailable();
    }
  }
  return temporaryStorage.get(key) ?? null;
}

function write(key, value) {
  const account=/^profile:([1-9][0-9]{0,14}):/.exec(key)?.[1];
  if(account&&typeof tornTrainingRecovery!=="undefined"&&tornTrainingRecovery.journalHeld(localStorage,account)){
    const message=byId("storage-message");
    message.textContent="Account restore is pending. Resolve it in Settings → Data & Backup before changing account data.";
    message.hidden=false;return;
  }
  if (value === null) temporaryStorage.delete(key);
  else temporaryStorage.set(key, value);
  if (persistent) {
    try {
      if(account&&typeof tornAccountStorage!=="undefined")tornAccountStorage.trackedWrite(localStorage,account,prefix+key,value);
      else if (value === null) localStorage.removeItem(prefix + key);
      else localStorage.setItem(prefix + key, value);
    } catch {
      markStorageUnavailable();
    }
  }
}

function profileKey(name) {
  return "profile:" + encodeURIComponent(name.toLowerCase()) + ":";
}

function activeKey(field) {
  return profileKey(activeProfile) + field;
}

function icon(name) {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;
}

function renderDirectory() {
  document.querySelector('[data-icon="home"]').innerHTML = icon("home");
  byId("section-nav").innerHTML = Object.entries(topics).map(([id, topic]) =>
    `<a class="nav-link" href="#${id}"><span class="icon">${icon(id)}</span>${topic.title}</a>`
  ).join("");
  byId("section-grid").innerHTML = Object.entries(topics).map(([id, topic]) =>
    `<a class="section-card" href="#${id}"><span class="icon">${icon(id)}</span>
      <span><strong>${topic.title}</strong><small>${topic.summary}</small></span>
      <span class="card-arrow" aria-hidden="true">›</span></a>`
  ).join("");
}

let lastApiConnectionError="",lastApiErrorSyncStamp=0;
function updateApiStatus(){
  const connected=tornGuideApi.isConnected(),status=byId("api-status"),state=tornGuideApi.state;
  if(connected&&lastApiConnectionError&&state.updated&&Number(state.updated)>lastApiErrorSyncStamp &&
      !Object.keys(state.errors||{}).length&&!Object.keys(state.inventoryErrors||{}).length){
    lastApiConnectionError="";
  }
  const failures=[
    ...Object.entries(state.errors||{}).map(([name,reason])=>name+": "+String(reason)),
    ...Object.entries(state.inventoryErrors||{}).map(([name,reason])=>"Inventory "+name+": "+String(reason))
  ];
  if(lastApiConnectionError&&!failures.length)failures.push(lastApiConnectionError);
  const error=failures.length>0;
  const kind=error?"error":connected?"ok":"idle";
  status.className="api-status api-status-"+kind;
  status.textContent=error?"×":connected?"✓":"·";
  const label=error?("Torn API error: "+failures.join("; ")) :
    connected?"Torn API connected; all requested sections healthy":"Torn API not connected";
  status.title=label;
  status.setAttribute("aria-label",label);
}
function updateSidebarCharacter(){
  const state=tornGuideApi.state,identity=state.identity,connected=tornGuideApi.isConnected();
  byId("sidebar-character-name").textContent=connected?(identity?.name||"Character"):"Connect Torn API";
  byId("sidebar-character-id").textContent=connected&&identity?.id!=null?"[#"+identity.id+"]":"";
  const details=byId("sidebar-character-details");
  if(!connected){
    details.innerHTML='<a class="sidebar-account-link" href="#profile">Connect your account to see details</a>';
    return;
  }
  const money=payload("money","money"),merits=payload("merits","merits"),
    bars=payload("bars","bars");
  const wallet=money?.wallet!=null?"$"+formatNumber(money.wallet):"Not loaded";
  details.innerHTML='<dl class="sidebar-facts">'+
    homePair("Money",wallet,"home-money")+
    homePair("Level",identity?.level??"Not loaded")+
    homePair("Points",money?.points??"Not loaded")+
    homePair("Merits",merits?.available??"Not loaded")+
    '</dl><div class="sidebar-bars">'+
    ["energy","nerve","happy","life"].map(key=>homeBar(key,bars?.[key])).join("")+'</div>';
}
function renderProfile() {
  byId("profile-link").textContent = activeProfile
    ? activePlayerName+" [#"+activeProfile+"]" : "Connect API";
  byId("settings-signout").disabled=!tornGuideApi.isConnected();
  tornBackupUI.sync();
  updateApiStatus();
  updateSidebarCharacter();
  byId("profile-summary").textContent = activeProfile
    ? "Connected as " + activePlayerName + ". " + (tornGuideApi.isRemembering()
      ? "This browser remembers your API key and last refreshed account data."
      : "This is a session-only connection; your API key is forgotten on reload.")
    : "Connect your Torn API key to load your stats and inventory. Opt into Stay logged in only on a private, trusted browser.";
  byId("remember-active").checked=tornGuideApi.isRemembering();
  updateRefreshUI();
  byId("profile-form").hidden = Boolean(activeProfile);
  byId("profile-actions").hidden = !activeProfile;
  byId("profile-name").value = "";
}

function chapter(title, content) {
  return `<div class="panel"><div class="panel-heading"><h2>${title}</h2></div>
    <div class="panel-content">${content}</div></div>`;
}

function renderTopic(route) {
  const topic = topics[route];
  const guest = '<p><a href="#profile">Open a local profile</a> to save progress in this browser.</p>';
  const view = byId("topic-view");
  if (route === "checklist") { view.innerHTML = tornRoadmap.render(); tornRoadmap.wire(view); return; }
  if (route === "calendar") {view.innerHTML=tornCrimeGuide.renderCalendar();tornCrimeGuide.wireCalendar(view);return;}
  if (route === "log") {view.innerHTML=tornLogGuide.render();tornLogGuide.wire(view);tornLogGuide.request();return;}
  if (route === "stats") { view.innerHTML = tornStatPlanner.render()+tornToolsGuide.contextLinks("stats"); tornStatPlanner.wire(view); return; }
  if (route === "racing") { view.innerHTML = tornRacingGuide.render()+tornToolsGuide.contextLinks("racing"); tornRacingGuide.wire(view); return; }
  if (route === "crime") { view.innerHTML = tornCrimeGuide.render()+tornToolsGuide.contextLinks("crime"); if(activeProfile)wireNotes("crime"); return; }
  if (route === "merits") { view.innerHTML=tornMeritGuide.render();tornMeritGuide.wire(view);return; }
  if (route === "education") { view.innerHTML = renderEducationPage(); wireEducationPage(view); return; }
  if (route === "stocks") { view.innerHTML = '<h1 id="topic-title" tabindex="-1" class="sr-only">Stocks</h1>'+renderStocksPanel(); wireStocksPanel(view); return; }
  if (route === "inventory") { view.innerHTML = renderInventoryPage()+tornToolsGuide.contextLinks("inventory"); return; }
  if (route === "jobs") { view.innerHTML = tornJobsGuide.render(); tornJobsGuide.wire(view); return; }
  if (route === "tools") { view.innerHTML = tornToolsGuide.render(); tornToolsGuide.wire(view); return; }
  const taskList = `<p id="task-progress" role="status"></p><div class="checklist">${Object.entries(tasks).map(([id, label]) =>
    `<label><input type="checkbox" name="${id}" ${activeProfile ? "" : "disabled"}><span>${label}</span></label>`
  ).join("")}</div>`;
  const notes = `<form id="note-form" class="note-form">
    <label for="topic-note">Personal notes</label>
    <textarea id="topic-note" maxlength="5000" rows="5"></textarea>
    <button class="button primary" type="submit">Save notes</button>
    <p class="feedback" id="note-feedback" role="status"></p>
    </form>`;

  view.innerHTML = `<header class="panel topic-header">
    <h1 id="topic-title" tabindex="-1">${topic.title}</h1><p>${topic.intro}</p></header>
    <div class="topic-grid">${route === "checklist"
      ? chapter("Your routine", (activeProfile ? "" : guest) + taskList)
      : chapter("Getting started", `<ul>${topic.prompts.map((item) => `<li>${item}</li>`).join("")}</ul>`)
        + chapter("Your notes", activeProfile ? notes : guest)}</div>`;


  if (["money","war","attacking"].includes(route)) view.innerHTML += tornToolsGuide.contextLinks(route);

  if (route === "checklist") wireChecklist(view);
  else if (activeProfile) wireNotes(route);
}

function wireChecklist(view) {
  const boxes = [...view.querySelectorAll('.checklist input[type="checkbox"]')];
  function updateProgress() {
    const total = boxes.filter((box) => box.checked).length;
    byId("task-progress").textContent = `${total} of ${boxes.length} complete`;
  }
  for (const box of boxes) {
    if (!activeProfile) break;
    const key = activeKey("task:" + box.name);
    box.checked = read(key) === "done";
    box.addEventListener("change", () => {
      write(key, box.checked ? "done" : null);
      updateProgress();
    });
  }
  updateProgress();
}

function wireNotes(route) {
  const field = byId("topic-note");
  const key = activeKey("notes:" + route);
  field.value = read(key) ?? "";
  field.addEventListener("input", () => { byId("note-feedback").textContent = ""; });
  byId("note-form").addEventListener("submit", (event) => {
    event.preventDefault();
    write(key, field.value || null);
    byId("note-feedback").textContent = persistent ? "Notes saved in this browser." : "Notes saved for this visit.";
  });
}

function renderRoute() {
  const hash = location.hash.slice(1);
  const route = hash === "quickstart" ? "checklist" : hash === "dashboard" ? "home" : (Object.hasOwn(topics, hash) || hash === "profile" ? hash : "home");
  const isTopic = Object.hasOwn(topics, route);
  const navRoute = isTopic ? route : "home";
  tornToolsGuide.updateBar(route);
  tornRightRail.render(route);
  byId("home-grid").hidden = route !== "profile" && (route !== "home" || tornGuideApi.isConnected());
  byId("topic-view").hidden = !isTopic && route !== "home";
  for (const link of document.querySelectorAll(".nav-link")) {
    if (link.hash === "#" + navRoute) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  if (isTopic) renderTopic(route);
  else if (route === "home") { const view=byId("topic-view");view.innerHTML=renderDashboard();tornCrimeGuide.wireRecommendations(view); }
  document.title = isTopic ? `${topics[route].title} · Torn City Guide` : route === "home" ? "Home · Torn City Guide" : "Torn City Guide";
  closeMenu();
  if (lastRoute !== route && (lastRoute !== undefined || route === "profile")) {
    const heading = byId(route === "profile" ? "profile-title" : "topic-title");
    heading.focus({ preventScroll: true });
    if (route === "profile") byId("profile").scrollIntoView({ block: "nearest" });
    else window.scrollTo(0, 0);
  }
  lastRoute = route;
  // A route change only loads selections required by that page. Each endpoint
  // has its own TTL and failure-backoff; navigating within cached pages is free.
  if(tornGuideApi.isConnected() && route !== "profile")
    tornGuideApi.loadPage(route).then(()=>{if(route==="inventory")return tornGuideApi.checkGearDaily();}).catch(error=>{
      byId("refresh-status").textContent=String(error.message||error);
    });
}

function closeMenu() {
  byId("guide-nav").classList.remove("is-open");
  byId("menu-button").setAttribute("aria-expanded", "false");
}

renderDirectory();
const sidebarDisclosure=byId("sidebar-character");
sidebarDisclosure.open=read("sidebar:expanded")==="1";
sidebarDisclosure.addEventListener("toggle",()=>{
  write("sidebar:expanded",sidebarDisclosure.open?"1":"0");
});
renderProfile();
tornTctClock.init();
tornRightRail.init();
renderRoute();
window.addEventListener("hashchange", renderRoute);
// Other current-version tabs immediately refresh a changed recovery hold.
// Reload resets cached account settings after an import or explicit release.
window.addEventListener("storage",event=>{
  const id=tornGuideApi.state.identity?.id;
  if(id!=null&&(event.key===null||event.key==="torn-city-guide:training-session-review:v1:"+id||event.key==="torn-city-guide:restore-journal:v1:"+id)){
    if(event.newValue===null&&event.key!==null){location.reload();return;}
    renderRoute();
  }
});
document.getElementById("topic-view").addEventListener("click",async event=>{
  const btn=event.target.closest("[data-home-activity-refresh]");
  if(!btn||!tornGuideApi.isConnected()||btn.disabled)return;
  btn.disabled=true;btn.textContent="Updating…";
  try{
    await tornGuideApi.loadPage("activity");
  }catch(error){
    const status=document.getElementById("home-activity-status");
    if(status)status.textContent=String(error.message||error);
  }finally{
    btn.disabled=false;btn.textContent="Update activity";
  }
});

byId("profile-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = byId("profile-name");
  const feedback = byId("profile-feedback");
  const button = byId("connect-api");
  button.disabled = true; feedback.textContent = "Connecting directly to Torn API…";
  try {
    const identity = await tornGuideApi.connect(input.value,byId("stay-logged-in").checked);
    lastApiConnectionError="";
    input.value = "";
    activeProfile = String(identity.id);
    activePlayerName = identity.name;
    // Ask the optional extension for a previously manually shared snapshot
    // before deciding whether the bars API selection is stale.
    tornGuideLocalBridge.request();
    write("active", null);
    renderProfile();
    renderRoute();
    feedback.textContent = "Connected. Loading your account data…";
    const status = await tornGuideApi.refresh();
    feedback.textContent = "Connected as " + activePlayerName + ". " +
      (status && status.failures ? status.failures + " sections unavailable; check Dashboard." : "Data loaded.") +
      (tornGuideApi.state.storageWarning ? " " + tornGuideApi.state.storageWarning : "");
    updateRefreshUI();
  } catch (error) {
    lastApiErrorSyncStamp=Number(tornGuideApi.state.updated)||0;
    lastApiConnectionError=String(error.message||error||"Could not connect to Torn.");
    input.value = "";
    feedback.textContent = lastApiConnectionError;
    updateApiStatus();
  } finally { button.disabled = false; }
});

function disconnectAccount() {
  lastApiConnectionError="";
  tornGuideApi.disconnect();
  activeProfile = null; activePlayerName = "";
  write("active", null);
  byId("stay-logged-in").checked=false;
  renderProfile();
  renderRoute();
  updateRefreshUI();
  byId("profile-feedback").textContent = "Disconnected. Saved API key and account cache cleared. Your notes and checklists remain saved locally.";
}
byId("switch-profile").addEventListener("click", () => {
  disconnectAccount();
  byId("profile-name").focus();
});
byId("sign-out").addEventListener("click", () => {
  disconnectAccount();
  byId("profile-name").focus();
});
function sinceSync(timestamp){
  if(!timestamp)return "--:--";
  const elapsed=Math.max(0,Math.floor((Date.now()-timestamp)/1000));
  const h=Math.floor(elapsed/3600),m=Math.floor(elapsed%3600/60),sec=elapsed%60;
  return h?String(h).padStart(2,"0")+":"+String(m).padStart(2,"0")+":"+String(sec).padStart(2,"0"):
    String(m).padStart(2,"0")+":"+String(sec).padStart(2,"0");
}
function updateSyncCounter(){
  const state=tornGuideApi.state,top=byId("refresh-top");
  const connected=tornGuideApi.isConnected(),stamp=state.updated;
  byId("refresh-age").textContent=connected?sinceSync(stamp):"--:--";
  const when=stamp?tornGuidePreferences.formatDate(stamp):"Not yet synchronized";
  const label=!connected?"Connect Torn API to refresh":state.loading?"Synchronizing Torn account":
    "Refresh this page's Torn data. Last sync: "+when+
    (state.cached?" (restored cache)":"");
  top.title=label;
  top.setAttribute("aria-label",label);
}
function updateRefreshUI(){
  updateApiStatus();
  updateSidebarCharacter();
  tornRightRail.render(tornGuideApi.routeName());
  const connected=tornGuideApi.isConnected();
  const busy=tornGuideApi.state.loading;
  const top=byId("refresh-top"),profile=byId("refresh-data");
  top.disabled=!connected||busy;
  profile.disabled=!connected||busy;
  top.classList.toggle("is-syncing",busy);
  byId("remember-active").checked=tornGuideApi.isRemembering();
  byId("settings-signout").disabled=!connected;
  const updated=tornGuideApi.state.updated;
  byId("refresh-status").textContent=busy?"Refreshing Torn data":connected
    ? (updated?"Last Torn refresh "+tornGuidePreferences.formatDate(updated):"Connected; waiting for data")
    : "Torn API disconnected";
  updateSyncCounter();
}
async function refreshAccount(){
  if(!tornGuideApi.isConnected() || tornGuideApi.state.loading)return;
  const feedback=byId("profile-feedback");
  feedback.textContent="Refreshing your Torn data…";
  updateRefreshUI();
  try{
    const result=await tornGuideApi.refresh({route:tornGuideApi.routeName(),force:true,includeStatus:true,includeMerits:tornRightRail.meritsVisible()});
    if(!tornGuideApi.isConnected())return;
    if(!result?.failures)lastApiConnectionError="";
    feedback.textContent = result && result.failures
      ? result.failures+" section(s) unavailable. See Dashboard API diagnostics."
      : "Torn data refreshed.";
    if(tornGuideApi.state.storageWarning) feedback.textContent+=" "+tornGuideApi.state.storageWarning;
  }catch(error){
    lastApiErrorSyncStamp=Number(tornGuideApi.state.updated)||0;
    lastApiConnectionError=String(error.message||error);
    feedback.textContent=lastApiConnectionError;
  }finally{updateRefreshUI();}
}
for(const id of ["refresh-data","refresh-top"])
  byId(id).addEventListener("click",refreshAccount);
byId("remember-active").addEventListener("change",event=>{
  const actual=tornGuideApi.setRemember(event.target.checked);
  event.target.checked=actual;
  byId("profile-feedback").textContent=actual
    ? "Stay logged in enabled: this browser will keep your API key and cached account data."
    : (tornGuideApi.state.storageWarning || "Stay logged in disabled; stored API key and cached data cleared.");
  renderProfile();
});
window.addEventListener("torn-guide-sync",updateRefreshUI);
setInterval(()=>{updateSyncCounter();updateHomeLiveBars();tornToolsGuide.tickStatus();tornRightRail.tick();tornRoadmap.tickOngoing();tornCrimeGuide.tickGrowth();tornLogGuide.tick();updateInventoryAges();for(const el of document.querySelectorAll("[data-edu-deadline]"))el.textContent=tornTctClock.formatDuration((Number(el.dataset.eduDeadline)-Date.now())/1000);},1000); // local UI ticks; active Energy watcher independently rate-limits read-only API checks

// The ellipsis is an unframed button; settings remain independent of API login.
function syncSettingsControls(){
  byId("setting-theme").value=tornGuidePreferences.get("theme");
  byId("setting-timezone").value=tornGuidePreferences.get("timeZone");
  byId("setting-links").value=tornGuidePreferences.get("externalMode");
  byId("setting-contextual").checked=tornGuidePreferences.get("contextualQuickAccess");
  byId("settings-signout").disabled=!tornGuideApi.isConnected();
  tornBackupUI.sync();
}
function closeSettings(){
  byId("settings-panel").hidden=true;
  byId("settings-toggle").setAttribute("aria-expanded","false");
}
function toggleSettings(){
  const panel=byId("settings-panel"),next=panel.hidden;
  if(next){syncSettingsControls();tornGuideLocalBridge.checkVersion();}
  panel.hidden=!next;
  byId("settings-toggle").setAttribute("aria-expanded",String(next));
}
byId("setting-timezone").innerHTML=tornGuidePreferences.zones.map(([id,name])=>
  '<option value="'+id+'">'+name+'</option>').join("");
tornGuidePreferences.init();
tornBackupUI.wire();
// Coalesced local-only revision capture. Do not infer an owner from a
// disconnected profile; export/import still requires fresh API verification.
const revisionQueue=tornAccountRevisions.createCaptureQueue({
  current:()=>{
    const id=tornGuideApi.state.identity?.id;
    if(!tornGuideApi.isConnected()||id==null||tornTrainingRecovery.journalHeld(localStorage,id))return null;
    return {id:String(id),isCurrent:()=>tornGuideApi.isConnected()&&String(tornGuideApi.state.identity?.id)===String(id)};
  },
  capture:scope=>tornAccountStorage.withRecoveryLock(scope.id,navigator.locks,()=>tornAccountRevisions.capture(localStorage,scope.id,scope.isCurrent)),
  report:error=>{const el=byId("backup-revision-status");if(el)el.textContent=error?"Revision tracking pending: "+error:"Local revision tracking up to date. External backup is still required.";}
});
window.addEventListener("torn-account-write",()=>revisionQueue.request());
window.addEventListener("torn-guide-sync",()=>revisionQueue.request());
window.addEventListener("storage",event=>{
  const id=tornGuideApi.state.identity?.id;if(id==null||!event.key)return;
  if(tornAccountStorage.sectionForKey(id,event.key)||event.key.startsWith("torn-city-guide:revision-observed-delete:v1:"+id+":"))revisionQueue.request();
});
document.addEventListener("visibilitychange",()=>{if(!document.hidden)revisionQueue.request();});
syncSettingsControls();
byId("settings-toggle").addEventListener("click",toggleSettings);
document.addEventListener("click",event=>{
  if(!byId("settings-panel").hidden&&!event.target.closest("#settings-widget"))closeSettings();
});
document.addEventListener("keydown",event=>{
  if(event.key==="Escape"&&!byId("settings-panel").hidden){
    closeSettings();byId("settings-toggle").focus();
  }
});
for(const [id,key] of [
  ["setting-theme","theme"],["setting-timezone","timeZone"],
  ["setting-links","externalMode"]
]){
  byId(id).addEventListener("change",event=>{
    if(!tornGuidePreferences.set(key,event.target.value))return;
    updateRefreshUI();
    if(key==="timeZone"&&location.hash==="#home")renderRoute();
  });
}
byId("setting-contextual").addEventListener("change",event=>{
  tornGuidePreferences.set("contextualQuickAccess",event.target.checked);
  tornToolsGuide.updateBar(tornGuideApi.routeName());
});
byId("settings-account").addEventListener("click",closeSettings);
byId("settings-signout").addEventListener("click",()=>{
  if(!tornGuideApi.isConnected())return;
  disconnectAccount();
  closeSettings();
});
window.addEventListener("torn-guide-preferences",()=>{
  tornToolsGuide.updateBar(tornGuideApi.routeName());
});

byId("topic-view").addEventListener("click",async event=>{
  const button=event.target.closest("[data-inventory-load]");
  if(!button)return;
  const category=button.dataset.inventoryLoad;
  if(!tornGuideApi.inventoryTypes.includes(category))return;
  const alreadyLoaded=Object.hasOwn(tornGuideApi.state.inventory,category);
  button.disabled=true;button.setAttribute("aria-busy","true");
  try{await tornGuideApi.loadInventory(category,alreadyLoaded);await tornGuideApi.checkGearDaily();}
  catch(error){byId("refresh-status").textContent=String(error.message||error);}
  finally{
    // A successful request rerenders Inventory, replacing this button.
    if(button.isConnected){button.disabled=false;button.removeAttribute("aria-busy");}
  }
});


// Torn Report's own CSP / X-Frame-Options and login policies determine whether
// the preview iframe works. Never proxy, frame-bust or fetch Torn Report privately.
let activeReport=null;
const reportDialog=byId("report-dialog"),reportFrame=byId("report-frame");
document.addEventListener("click",event=>{
  const button=event.target.closest("[data-report]");
  if(!button)return;
  const record=tornReportCatalog[button.dataset.report];
  if(!record)return;
  activeReport=record;
  byId("report-dialog-title").textContent=record[0]+" · Torn Report";
  byId("report-external").href=record[1];
  reportFrame.title=record[0]+" · Torn Report embedded preview";
  // Assign the URL only in direct response to this user click. This does not
  // trigger any extra Torn API calls or expose the connected Torn API key.
  reportFrame.src=record[1];
  if(typeof reportDialog.showModal==="function")reportDialog.showModal();
  else window.open(record[1],"_blank","noopener,noreferrer");
});
const closeReport=()=>{if(reportDialog.open)reportDialog.close();};
byId("report-close").addEventListener("click",closeReport);
byId("report-dialog-done").addEventListener("click",closeReport);
reportDialog.addEventListener("close",()=>{reportFrame.removeAttribute("src");activeReport=null;});
reportDialog.addEventListener("click",event=>{
  if(event.target===reportDialog)closeReport();
});
byId("report-popout").addEventListener("click",()=>{
  if(!activeReport)return;
  const popup=window.open(activeReport[1],"torn-report-view","popup,width=1200,height=800,resizable=yes,scrollbars=yes");
  if(popup)popup.focus();
  // The always-visible 'Open in new tab' link remains the fallback if the
  // browser blocks custom popup windows.
});

byId("menu-button").addEventListener("click", () => {
  const open = byId("guide-nav").classList.toggle("is-open");
  byId("menu-button").setAttribute("aria-expanded", String(open));
  if (open) byId("guide-nav").querySelector("a").focus();
});

byId("guide-nav").addEventListener("keydown", (event) => {
  if (event.key === "Escape" && byId("guide-nav").classList.contains("is-open")) {
    closeMenu();
    byId("menu-button").focus();
  }
});

byId("guide-nav").addEventListener("click", (event) => {
  const link = event.target.closest(".nav-link");
  if (link?.hash === location.hash) {
    closeMenu();
    byId("topic-title")?.focus();
  }
});

document.querySelector(".skip-link").addEventListener("click", (event) => {
  event.preventDefault();
  byId("main").focus();
});


// Resume a previously authorized, opt-in browser session without prompting again.
// Show cached data immediately. Refresh now only when the last snapshot is stale.
const resumed=tornGuideApi.restore();
if(resumed){
  activeProfile=String(resumed.identity.id);
  activePlayerName=resumed.identity.name;
  tornGuideLocalBridge.request();
  renderProfile();
  renderRoute();
  byId("profile-feedback").textContent=resumed.cached
    ? "Restored your locally cached Torn profile. Automatic updates are enabled while this page is open."
    : "Reconnected with your stored API key. Loading account data…";
  tornGuideApi.refreshOnResume();revisionQueue.request();
}else{
  updateRefreshUI();
}
