const authNotice = document.getElementById("authNotice");
const optionsPanel = document.getElementById("optionsPanel");
const domainList = document.getElementById("domainList");
const domainCount = document.getElementById("domainCount");
const optionsForm = document.getElementById("optionsForm");
const reloadButton = document.getElementById("reloadButton");
const optionsError = document.getElementById("optionsError");

function sendMessage(message) {
  return new Promise((resolve) => {
    chrome.runtime.sendMessage(message, resolve);
  });
}

function setError(message) {
  if (!message) {
    optionsError.textContent = "";
    optionsError.classList.add("hidden");
    return;
  }

  optionsError.textContent = message;
  optionsError.classList.remove("hidden");
}

function normalizeInput(text) {
  return text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .join("\n");
}

async function refreshOptions() {
  const response = await sendMessage({ type: "getState" });
  if (!response || !response.ok) {
    authNotice.textContent = "Could not load state.";
    return;
  }

  if (!response.authenticated) {
    authNotice.textContent = "Unlock with the dashboard first, then return here to edit domains.";
    optionsPanel.classList.add("hidden");
    return;
  }

  authNotice.classList.add("hidden");
  optionsPanel.classList.remove("hidden");
  domainList.value = response.blockedDomains.join("\n");
  domainCount.textContent = String(response.blockedDomains.length);
}

optionsForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError("");

  const response = await sendMessage({
    type: "updateBlockedDomains",
    blockedDomains: normalizeInput(domainList.value).split(/\n/)
  });

  if (!response || !response.ok) {
    setError(response && response.error ? response.error : "Could not save domains");
    return;
  }

  await refreshOptions();
});

reloadButton.addEventListener("click", async () => {
  setError("");
  await refreshOptions();
});

refreshOptions();
