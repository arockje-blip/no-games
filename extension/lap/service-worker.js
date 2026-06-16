const DEFAULT_BLOCKED_DOMAINS = [
  "roblox.com",
  "rbxcdn.com",
  "epicgames.com",
  "store.epicgames.com",
  "steamcommunity.com",
  "store.steampowered.com",
  "steampowered.com",
  "battle.net",
  "blizzard.com",
  "riotgames.com",
  "playvalorant.com",
  "ea.com",
  "origin.com",
  "ubisoft.com",
  "ubisoftconnect.com",
  "nintendo.com",
  "playstation.com",
  "xbox.com",
  "minecraft.net",
  "mojang.com",
  "gog.com",
  "itch.io",
  "crazygames.com",
  "poki.com",
  "miniclip.com",
  "friv.com",
  "kongregate.com",
  "armorgames.com",
  "newgrounds.com",
  "coolmathgames.com",
  "y8.com",
  "kizi.com",
  "silvergames.com",
  "addictinggames.com",
  "kbhgames.com",
  "gameflare.com",
  "gamepix.com",
  "mess.eu.org",
  "mediafire.com",
  "mega.nz",
  "uptodown.com",
  "softonic.com",
  "filehippo.com",
  "sourceforge.net",
  "download.cnet.com",
  "apkcombo.com",
  "apkpure.com",
  "filehorse.com",
  "getintopc.com",
  "steamunlocked.net",
  "fitgirl-repacks.site"
];

const AUTH = Object.freeze({
  username: "AJ_encoded",
  password: "19782004"
});

const AUTH_SESSION_KEY = "lap_authenticated_until";
const BLOCKING_ALARM = "lap_resume_blocking";
const ALLOWED_DURATIONS = new Set([2, 5, 10, 15, 25, 35, 50, 60]);

function normalizeDomain(entry) {
  if (typeof entry !== "string") {
    return "";
  }

  let value = entry.trim().toLowerCase();
  if (!value) {
    return "";
  }

  value = value.replace(/^https?:\/\//, "");
  value = value.replace(/^\*\./, "");
  value = value.split(/[/?#]/)[0];
  value = value.replace(/^\.+/, "").replace(/\.+$/, "");

  if (!value || !value.includes(".") || !/^[a-z0-9.-]+$/.test(value)) {
    return "";
  }

  return value;
}

function normalizeDomainList(list) {
  const uniqueDomains = new Set();

  for (const item of Array.isArray(list) ? list : []) {
    const normalized = normalizeDomain(item);
    if (normalized) {
      uniqueDomains.add(normalized);
    }
  }

  return [...uniqueDomains];
}

async function readSettings() {
  const defaults = {
    blockedDomains: DEFAULT_BLOCKED_DOMAINS,
    disabledUntil: 0
  };

  const stored = await chrome.storage.local.get(defaults);
  const blockedDomains = normalizeDomainList(stored.blockedDomains);

  return {
    blockedDomains: blockedDomains.length ? blockedDomains : DEFAULT_BLOCKED_DOMAINS,
    disabledUntil: Number(stored.disabledUntil) || 0
  };
}

async function readAuthState() {
  const stored = await chrome.storage.session.get({ [AUTH_SESSION_KEY]: 0 });
  return Number(stored[AUTH_SESSION_KEY]) || 0;
}

async function isAuthenticated() {
  return (await readAuthState()) > Date.now();
}

async function requireAuthentication() {
  if (!(await isAuthenticated())) {
    throw new Error("Authentication required");
  }
}

function buildRules(blockedDomains) {
  const rules = blockedDomains.map((domain, index) => ({
    id: index + 1,
    priority: 1,
    action: {
      type: "block"
    },
    condition: {
      urlFilter: `||${domain}^`,
      resourceTypes: [
        "main_frame",
        "sub_frame",
        "xmlhttprequest",
        "script",
        "image",
        "stylesheet",
        "font",
        "other"
      ]
    }
  }));

  return rules;
}

async function replaceBlockingRules(blockedDomains) {
  const existingRules = await chrome.declarativeNetRequest.getDynamicRules();
  const removeRuleIds = existingRules.map((rule) => rule.id);

  await chrome.declarativeNetRequest.updateDynamicRules({
    removeRuleIds,
    addRules: buildRules(blockedDomains)
  });
}

async function syncBlockingState() {
  const settings = await readSettings();
  const disabledUntil = Number(settings.disabledUntil) || 0;
  const isPaused = disabledUntil > Date.now();

  if (isPaused) {
    await replaceBlockingRules([]);
    chrome.alarms.create(BLOCKING_ALARM, { when: disabledUntil });
    return {
      ...settings,
      disabledUntil
    };
  }

  if (disabledUntil) {
    await chrome.storage.local.set({ disabledUntil: 0 });
  }

  await replaceBlockingRules(settings.blockedDomains);
  await chrome.alarms.clear(BLOCKING_ALARM);

  return {
    ...settings,
    disabledUntil: 0
  };
}

async function authenticate(username, password) {
  if (username !== AUTH.username || password !== AUTH.password) {
    return {
      ok: false,
      error: "Invalid username or password"
    };
  }

  const authenticatedUntil = Date.now() + 60 * 60 * 1000;
  await chrome.storage.session.set({ [AUTH_SESSION_KEY]: authenticatedUntil });

  return {
    ok: true,
    authenticatedUntil
  };
}

async function pauseBlocking(minutes) {
  await requireAuthentication();

  const duration = Number(minutes);
  if (!ALLOWED_DURATIONS.has(duration)) {
    throw new Error("Unsupported duration");
  }

  const disabledUntil = Date.now() + duration * 60 * 1000;
  await chrome.storage.local.set({ disabledUntil });
  await syncBlockingState();

  return {
    ok: true,
    disabledUntil
  };
}

async function resumeBlocking() {
  await requireAuthentication();
  await chrome.storage.local.set({ disabledUntil: 0 });
  await syncBlockingState();

  return {
    ok: true,
    disabledUntil: 0
  };
}

async function updateBlockedDomains(blockedDomains) {
  await requireAuthentication();

  const sanitizedDomains = normalizeDomainList(blockedDomains);
  if (!sanitizedDomains.length) {
    throw new Error("Add at least one valid domain");
  }

  await chrome.storage.local.set({ blockedDomains: sanitizedDomains });
  await syncBlockingState();

  return {
    ok: true,
    blockedDomains: sanitizedDomains
  };
}

async function getState() {
  const settings = await readSettings();
  const authenticatedUntil = await readAuthState();
  const now = Date.now();

  return {
    ok: true,
    authenticated: authenticatedUntil > now,
    authenticatedUntil,
    blockedDomains: settings.blockedDomains,
    disabledUntil: settings.disabledUntil,
    paused: settings.disabledUntil > now
  };
}

chrome.runtime.onInstalled.addListener(async () => {
  await chrome.storage.local.set({
    blockedDomains: DEFAULT_BLOCKED_DOMAINS,
    disabledUntil: 0
  });
  await syncBlockingState();
});

chrome.runtime.onStartup.addListener(async () => {
  await syncBlockingState();
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name !== BLOCKING_ALARM) {
    return;
  }

  await chrome.storage.local.set({ disabledUntil: 0 });
  await syncBlockingState();
});

chrome.commands.onCommand.addListener(async (command) => {
  if (command !== "open-dashboard") {
    return;
  }

  await chrome.tabs.create({ url: chrome.runtime.getURL("index.html") });
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  const action = message && message.type;

  (async () => {
    try {
      switch (action) {
        case "authenticate":
          sendResponse(await authenticate(message.username, message.password));
          break;
        case "getState":
          sendResponse(await getState());
          break;
        case "pauseBlocking":
          sendResponse(await pauseBlocking(message.minutes));
          break;
        case "resumeBlocking":
          sendResponse(await resumeBlocking());
          break;
        case "updateBlockedDomains":
          sendResponse(await updateBlockedDomains(message.blockedDomains));
          break;
        case "syncBlockingState":
          sendResponse(await syncBlockingState());
          break;
        default:
          sendResponse({ ok: false, error: "Unknown request" });
      }
    } catch (error) {
      sendResponse({
        ok: false,
        error: error instanceof Error ? error.message : "Unexpected error"
      });
    }
  })();

  return true;
});
