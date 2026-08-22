const ALARM_NAME = 'torn-travel-alert-check';
const DEFAULT_FILE_URL = 'file:///C:/Codex/TORN/RainMeter%20Projects/Travel%20Assistant/data/runtime/browser-notifications.json';
const TORN_TRAVEL_URL = 'https://www.torn.com/page.php?sid=travel';
const ICON_URL = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAYAAACqaXHeAAABZElEQVR4nO2bMUrEQBhGvxVbm7VRLBRrZS0EwcZywUvsCRY7D2Frb+8R7KwEwUbsxcrSxgNoNU0ymcnimsdMvlcugXn/yySBhZns7O3/aMRs0AI0DkAL0GyucvH57cc/aayfp+VBr+smfV6CJQ3eJBci+wiUPLyU908GKH34QGqOzgC1DB/omicaoLbhA7G5Rv8ZbAWo9e4HmvN5B9ACNA5AC9A4AC1A4wC0AM3oA6z0h8hf+Hp90OfjnSTp+/1FW4enkqTdi4W2Ty6H0mgxWIDpbK7pbC5Jer4+1tHV/VBLJxn9I+AAtACNA9ACNA5ALHp280YsG8U7gBagcQBagMYBaAEaB6AFaByAFqBxAFqAxgFoARoHoAVoHIAWoHEAWoDGAWgBGgegBWhaAfqetCiV5nzeAbEfa90Fsbk6d0BtEbrmST4CtURIzZF9B5QeIeff69hcoKTDFGs9N1gz/gzSAjS/aDs7G6/jBlgAAAAASUVORK5CYII=';

async function ensureDefaults() {
  const current = await chrome.storage.local.get({ fileUrl: '' });
  if (!current.fileUrl) {
    await chrome.storage.local.set({ fileUrl: DEFAULT_FILE_URL });
  }
}

async function ensureAlarm() {
  await chrome.alarms.create(ALARM_NAME, { periodInMinutes: 0.5 });
}

async function setBadge(text, color = '#52606d') {
  try {
    await chrome.action.setBadgeBackgroundColor({ color });
    await chrome.action.setBadgeText({ text });
  } catch (_) {
  }
}

async function readAlertState() {
  const config = await chrome.storage.local.get({ fileUrl: DEFAULT_FILE_URL });
  const fileUrl = String(config.fileUrl || '').trim();
  if (!fileUrl.startsWith('file:///')) {
    throw new Error('Alert file URL must be a file:/// URL.');
  }

  const allowed = await chrome.extension.isAllowedFileSchemeAccess();
  if (!allowed) {
    throw new Error('Enable Allow access to file URLs for this extension.');
  }

  const response = await fetch(fileUrl, { cache: 'no-store' });
  const text = await response.text();
  if (!text.trim()) {
    throw new Error('Alert file is empty.');
  }
  return JSON.parse(text);
}

async function showDueAlerts() {
  try {
    const state = await readAlertState();
    const now = Math.floor(Date.now() / 1000);

    if (!state || state.enabled !== true) {
      await setBadge('');
      return;
    }
    if (!Number.isFinite(Number(state.generatedAt)) || now - Number(state.generatedAt) > 180) {
      await setBadge('OLD', '#8a5a00');
      return;
    }

    const permission = await chrome.notifications.getPermissionLevel();
    if (permission !== 'granted') {
      await setBadge('!', '#9d2c2c');
      return;
    }

    const storage = await chrome.storage.local.get({ shownEvents: {} });
    const shownEvents = storage.shownEvents || {};
    const purgeBefore = now - (3 * 24 * 3600);
    for (const [key, shownAt] of Object.entries(shownEvents)) {
      if (Number(shownAt) < purgeBefore) {
        delete shownEvents[key];
      }
    }

    let displayed = 0;
    const events = Array.isArray(state.events) ? state.events : [];
    for (const event of events) {
      if (!event || !event.id || shownEvents[event.id]) {
        continue;
      }
      if (Number(event.expiresAt || 0) > 0 && Number(event.expiresAt) <= now) {
        continue;
      }

      const notificationId = `tta:${event.id}`;
      await chrome.notifications.create(notificationId, {
        type: 'basic',
        iconUrl: ICON_URL,
        title: String(event.title || 'Torn Travel Assistant'),
        message: String(event.message || 'Modeled foreign-stock window update.'),
        contextMessage: `${event.countryName || ''}${event.itemName ? ' | ' + event.itemName : ''}`,
        eventTime: Number(event.windowStartAt || now) * 1000,
        buttons: [{ title: 'Open Torn travel' }],
        priority: 1
      });
      shownEvents[event.id] = now;
      displayed += 1;
    }

    await chrome.storage.local.set({ shownEvents });
    await setBadge(displayed > 0 ? String(Math.min(displayed, 9)) : '');
  } catch (error) {
    console.warn('Torn Travel Assistant notification check failed:', error);
    await setBadge('!', '#9d2c2c');
  }
}

chrome.runtime.onInstalled.addListener(async () => {
  await ensureDefaults();
  await ensureAlarm();
  await showDueAlerts();
});

chrome.runtime.onStartup.addListener(async () => {
  await ensureDefaults();
  await ensureAlarm();
  await showDueAlerts();
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) {
    showDueAlerts();
  }
});

chrome.notifications.onClicked.addListener(async (notificationId) => {
  if (!notificationId.startsWith('tta:')) {
    return;
  }
  await chrome.tabs.create({ url: TORN_TRAVEL_URL });
  await chrome.notifications.clear(notificationId);
});

chrome.notifications.onButtonClicked.addListener(async (notificationId) => {
  if (!notificationId.startsWith('tta:')) {
    return;
  }
  await chrome.tabs.create({ url: TORN_TRAVEL_URL });
  await chrome.notifications.clear(notificationId);
});

ensureDefaults().then(ensureAlarm).then(showDueAlerts);
