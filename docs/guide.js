"use strict";

const topics = {
  checklist: {
    title: "Checklist",
    summary: "Milestones and daily routine",
    intro: "Your beginner roadmap and daily tasks in one checklist.",
  },
  faction: {
    title: "Faction",
    summary: "Find your place in a crew",
    intro: "Use this page to compare factions and remember what your crew expects from you.",
    prompts: ["Ask about activity requirements and war schedules.", "Check how armory access and payouts work.", "Write down who to contact for help."],
  },
  racing: { title: "Racing", summary: "Tracks, cars, upgrades and point saving", intro: "Reach Class A with points saved for a competitive car." },
  stats: {
    title: "Stats",
    summary: "Four-stat calculator and happy-jump comparator",
    intro: "Calculate gym gains, track perks, and compare natural energy with happy jumps.",
    prompts: ["Record a baseline for your four battle stats.", "Pick one short-term training goal.", "Set a date to compare your progress."],
  },
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
    summary: "Keep references handy",
    intro: "Use your notes to collect the references and tools you reach for while playing.",
    prompts: ["Save links to your preferred Torn resources.", "Write down what each tool helps you track.", "Keep API keys and other secrets out of your notes."],
  },
};

const icons = {
  dashboard: '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 10h18M10 10v11"/>',
  quickstart: '<path d="M4 12l5 5L20 6"/><path d="M4 4h16v16H4z"/>',
  home: '<path d="m3 10 9-7 9 7v10H3z"/><path d="M9 20v-7h6v7"/>',
  checklist: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V2h6v2m-7 8 2 2 5-5m-6 8h6"/>',
  faction: '<path d="M12 22s7-3 7-10V5l-7-3-7 3v7c0 7 7 10 7 10Z"/><path d="M12 8v7m-3-4h6"/>',
  stats: '<path d="M3 3v18h18M7 17v-5m5 5V8m5 9V5"/>',
  racing: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="4"/><path d="m12 12 4-7"/>',
  crime: '<path d="M3 11c0-4 4-7 9-7s9 3 9 7-4 8-9 8-9-4-9-8Z"/><circle cx="8" cy="11" r="2"/><circle cx="16" cy="11" r="2"/>',
  attacking: '<circle cx="12" cy="12" r="7"/><circle cx="12" cy="12" r="2"/><path d="M12 2v3m0 14v3M2 12h3m14 0h3"/>',
  war: '<path d="m4 4 5 1 10 10-4 4L5 9zM20 4l-5 1-3 3m-4 4-3 3 4 4 3-3m1 5 8-8M3 13l8 8"/>',
  money: '<rect x="3" y="6" width="18" height="12" rx="2"/><circle cx="12" cy="12" r="2.5"/><path d="M6 12h1m10 0h1"/>',
  tools: '<path d="M14 6a4 4 0 0 0-5 5L3 17a2 2 0 0 0 4 4l6-6a4 4 0 0 0 5-5l-3 3-4-4z"/>',
};

const tasks = {
  energy: "Decide how to spend your energy",
  nerve: "Check your nerve and plan a crime",
  faction: "Check faction messages and plans",
  money: "Review your cash and savings goal",
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
  if (value === null) temporaryStorage.delete(key);
  else temporaryStorage.set(key, value);
  if (persistent) {
    try {
      if (value === null) localStorage.removeItem(prefix + key);
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

function renderProfile() {
  byId("profile-link").textContent = activePlayerName || "Connect Torn API";
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
  if (route === "checklist") { view.innerHTML = renderQuickstart(); wireQuickstart(); wireChecklist(view); return; }
  if (route === "stats") { view.innerHTML = tornStatPlanner.render(); tornStatPlanner.wire(view); return; }
  if (route === "racing") { view.innerHTML = tornRacingGuide.render(); tornRacingGuide.wire(view); return; }
  if (route === "crime") { view.innerHTML = tornCrimeGuide.render(); if(activeProfile)wireNotes("crime"); return; }
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
  byId("home-grid").hidden = route !== "home" && route !== "profile";
  byId("topic-view").hidden = !isTopic && route !== "home";
  for (const link of document.querySelectorAll(".nav-link")) {
    if (link.hash === "#" + navRoute) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  if (isTopic) renderTopic(route);
  else if (route === "home") byId("topic-view").innerHTML = renderDashboard();
  document.title = isTopic ? `${topics[route].title} · Torn City Guide` : route === "home" ? "Home · Torn City Guide" : "Torn City Guide";
  closeMenu();
  if (lastRoute !== route && (lastRoute !== undefined || route === "profile")) {
    const heading = byId(route === "profile" ? "profile-title" : "topic-title");
    heading.focus({ preventScroll: true });
    if (route === "profile") byId("profile").scrollIntoView({ block: "nearest" });
    else window.scrollTo(0, 0);
  }
  lastRoute = route;
}

function closeMenu() {
  byId("guide-nav").classList.remove("is-open");
  byId("menu-button").setAttribute("aria-expanded", "false");
}

renderDirectory();
renderProfile();
renderRoute();
window.addEventListener("hashchange", renderRoute);

byId("profile-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const input = byId("profile-name");
  const feedback = byId("profile-feedback");
  const button = byId("connect-api");
  button.disabled = true; feedback.textContent = "Connecting directly to Torn API…";
  try {
    const identity = await tornGuideApi.connect(input.value,byId("stay-logged-in").checked);
    input.value = "";
    activeProfile = String(identity.id);
    activePlayerName = identity.name;
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
    input.value = "";
    feedback.textContent = error.message || "Could not connect to Torn.";
  } finally { button.disabled = false; }
});

function disconnectAccount() {
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
function updateRefreshUI(){
  const connected=tornGuideApi.isConnected();
  const busy=tornGuideApi.state.loading;
  const top=byId("refresh-top"),profile=byId("refresh-data");
  top.disabled=!connected||busy;
  profile.disabled=!connected||busy;
  top.textContent=busy?"↻ Updating…":"↻ Refresh";
  top.title=!connected?"Connect Torn API first":busy?"Torn account refresh in progress":"Refresh Torn data now";
  byId("remember-active").checked=tornGuideApi.isRemembering();
  const updated=tornGuideApi.state.updated;
  byId("refresh-status").textContent=busy?"Refreshing Torn data":connected
    ? (updated?"Last Torn refresh "+new Date(updated).toLocaleTimeString():"Connected; waiting for data")
    : "Torn API disconnected";
}
async function refreshAccount(){
  if(!tornGuideApi.isConnected() || tornGuideApi.state.loading)return;
  const feedback=byId("profile-feedback");
  feedback.textContent="Refreshing your Torn data…";
  updateRefreshUI();
  try{
    const result=await tornGuideApi.refresh();
    if(!tornGuideApi.isConnected())return;
    feedback.textContent = result && result.failures
      ? result.failures+" section(s) unavailable. See Dashboard API diagnostics."
      : "Torn data refreshed.";
    if(tornGuideApi.state.storageWarning) feedback.textContent+=" "+tornGuideApi.state.storageWarning;
  }catch(error){
    feedback.textContent=String(error.message||error);
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
  renderProfile();
  renderRoute();
  byId("profile-feedback").textContent=resumed.cached
    ? "Restored your locally cached Torn profile. Automatic updates are enabled while this page is open."
    : "Reconnected with your stored API key. Loading account data…";
  tornGuideApi.refreshOnResume();
}else{
  updateRefreshUI();
}
