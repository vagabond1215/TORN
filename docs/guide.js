"use strict";

const topics = {
  checklist: {
    title: "Checklist",
    summary: "Track your routine",
    intro: "Keep a short list of things to check when you play. Clear individual items whenever you’re ready to repeat them.",
  },
  faction: {
    title: "Faction",
    summary: "Find your place in a crew",
    intro: "Use this page to compare factions and remember what your crew expects from you.",
    prompts: ["Ask about activity requirements and war schedules.", "Check how armory access and payouts work.", "Write down who to contact for help."],
  },
  stats: {
    title: "Stats",
    summary: "Plan your gym training",
    intro: "Choose a training priority and track your progress in strength, defense, speed, and dexterity.",
    prompts: ["Record a baseline for your four battle stats.", "Pick one short-term training goal.", "Set a date to compare your progress."],
  },
  crime: {
    title: "Crime",
    summary: "Plan your nerve spending",
    intro: "Pick an in-game crime to practice and use your notes to track what works.",
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
  home: '<path d="m3 10 9-7 9 7v10H3z"/><path d="M9 20v-7h6v7"/>',
  checklist: '<rect x="5" y="4" width="14" height="17" rx="2"/><path d="M9 4V2h6v2m-7 8 2 2 5-5m-6 8h6"/>',
  faction: '<path d="M12 22s7-3 7-10V5l-7-3-7 3v7c0 7 7 10 7 10Z"/><path d="M12 8v7m-3-4h6"/>',
  stats: '<path d="M3 3v18h18M7 17v-5m5 5V8m5 9V5"/>',
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
let activeProfile = read("active");
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
  byId("profile-link").textContent = activeProfile || "Local profile";
  byId("profile-summary").textContent = activeProfile
    ? `Signed in as ${activeProfile}. Your checklist and notes stay in this browser.`
    : "Use a name to save your checklist and notes in this browser. No password or Torn account connection is needed.";
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
  const boxes = [...view.querySelectorAll('input[type="checkbox"]')];
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
  const route = Object.hasOwn(topics, hash) || hash === "profile" ? hash : "home";
  const isTopic = Object.hasOwn(topics, route);
  const navRoute = isTopic ? route : "home";
  byId("home-view").hidden = isTopic;
  byId("home-grid").hidden = isTopic;
  byId("topic-view").hidden = !isTopic;
  for (const link of document.querySelectorAll(".nav-link")) {
    if (link.hash === "#" + navRoute) link.setAttribute("aria-current", "page");
    else link.removeAttribute("aria-current");
  }
  if (isTopic) renderTopic(route);
  document.title = isTopic ? `${topics[route].title} · Torn City Guide` : "Torn City Guide";
  closeMenu();
  if (lastRoute !== route && (lastRoute !== undefined || route === "profile")) {
    const heading = byId(route === "profile" ? "profile-title" : isTopic ? "topic-title" : "home-title");
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

byId("profile-form").addEventListener("submit", (event) => {
  event.preventDefault();
  const field = byId("profile-name");
  const name = field.value.trim().normalize("NFC").toWellFormed();
  const feedback = byId("profile-feedback");
  if (!name) {
    feedback.textContent = "Enter a profile name.";
    field.focus();
    return;
  }
  const key = profileKey(name) + "name";
  activeProfile = read(key) ?? name;
  write(key, activeProfile);
  write("active", activeProfile);
  renderProfile();
  feedback.textContent = `Opened ${activeProfile}.`;
  byId("profile-title").focus({ preventScroll: true });
});

byId("switch-profile").addEventListener("click", () => {
  byId("profile-form").hidden = false;
  byId("profile-name").focus();
});

byId("sign-out").addEventListener("click", () => {
  activeProfile = null;
  write("active", null);
  renderProfile();
  byId("profile-feedback").textContent = "Signed out. You can reopen your profile by name.";
  byId("profile-name").focus();
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
    byId(lastRoute === "home" ? "home-title" : "topic-title")?.focus();
  }
});

document.querySelector(".skip-link").addEventListener("click", (event) => {
  event.preventDefault();
  byId("main").focus();
});
