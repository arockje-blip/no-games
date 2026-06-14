const DURATIONS = [2, 5, 10, 15, 25, 35, 50, 60];

const loginForm = document.getElementById("loginForm");
const usernameInput = document.getElementById("username");
const passwordInput = document.getElementById("password");
const loginError = document.getElementById("loginError");
const dashboardPanel = document.getElementById("dashboardPanel");
const durationButtons = document.getElementById("durationButtons");
const protectionState = document.getElementById("protectionState");
const sessionState = document.getElementById("sessionState");
const blockedCount = document.getElementById("blockedCount");
const pausedUntil = document.getElementById("pausedUntil");
const refreshButton = document.getElementById("refreshButton");
const resumeButton = document.getElementById("resumeButton");

function formatTimeStamp(value) {
  if (!value) {
    return "Never";
  }

  return new Date(value).toLocaleString();
}

function sendMessage(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, resolve);
  });
}

function setError(message) {
  if (!message) {
    loginError.textContent = "";
    loginError.classList.add("hidden");
    return;
  }

  loginError.textContent = message;
  loginError.classList.remove("hidden");
}

function renderDurationButtons() {
  durationButtons.innerHTML = "";

  for (const duration of DURATIONS) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = `${duration} min`;
    button.addEventListener("click", async () => {
      const response = await sendMessage({ type: "pauseBlocking", minutes: duration });
      if (!response || !response.ok) {
        setError(response && response.error ? response.error : "Could not pause blocking");
        return;
      }

      await refreshState();
    });
    durationButtons.appendChild(button);
  }
}

async function refreshState() {
  const response = await sendMessage({ type: "getState" });
  if (!response || !response.ok) {
    return;
  }

  protectionState.textContent = response.paused ? "Paused" : "Active";
  sessionState.textContent = response.authenticated ? "Unlocked" : "Locked";
  blockedCount.textContent = String(response.blockedDomains.length);
  pausedUntil.textContent = formatTimeStamp(response.disabledUntil);
  dashboardPanel.classList.toggle("hidden", !response.authenticated);
}

async function unlock(username, password) {
  const response = await sendMessage({ type: "authenticate", username, password });
  if (!response || !response.ok) {
    throw new Error(response && response.error ? response.error : "Unable to unlock");
  }

  setError("");
  dashboardPanel.classList.remove("hidden");
  await refreshState();
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  try {
    await unlock(usernameInput.value, passwordInput.value);
  } catch (error) {
    setError(error instanceof Error ? error.message : "Unable to unlock");
  }
});

refreshButton.addEventListener("click", async () => {
  await refreshState();
});

resumeButton.addEventListener("click", async () => {
  const response = await sendMessage({ type: "resumeBlocking" });
  if (!response || !response.ok) {
    setError(response && response.error ? response.error : "Could not re-enable protection");
    return;
  }

  await refreshState();
});

renderDurationButtons();
refreshState();
