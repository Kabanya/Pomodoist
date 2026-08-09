import {
  applyOptimisticCommand,
  formatClock,
  localeFor,
  remainingSeconds,
  textFor,
} from "./core.js";

const config = window.pomodoistRuntimeConfig ?? {};
const WebApp = window.Telegram?.WebApp;
const telegramContext = typeof WebApp?.initData === "string" &&
  WebApp.initData.length > 0;
const languageCode = telegramContext
  ? WebApp.initDataUnsafe?.user?.language_code ?? "en"
  : navigator.language;
const locale = localeFor(languageCode);
const text = textFor(locale);
const endpoint = `${config.supabaseUrl ?? ""}/functions/v1/pomodoist-telegram`;
const botName = config.environment === "staging"
  ? "pomodoist_test_bot"
  : "pomodoist_bot";
const draftKey = "pomodoist.telegram.draft.v1";
const pendingKey = "pomodoist.telegram.pending.v1";
const elements = Object.fromEntries(
  [...document.querySelectorAll("[id]")].map((
    element,
  ) => [element.id, element]),
);

let state = { account: { linked: false }, inbox: [], focus: null };
let serverState = state;
let pendingCommands = [];
let busy = false;
let lastCompleted = null;
let toastTimer;
let draftTimer;
let autoCompleting = false;
let storageWrites = Promise.resolve();
let serverGeneration = 0;

document.documentElement.lang = locale;
document.documentElement.dir = text.direction;
applyText();

if (!telegramContext) {
  elements.loading.hidden = true;
  elements.outside.hidden = false;
} else {
  WebApp.ready();
  WebApp.expand();
  bindTelegram();
  bindUi();
  start().catch(showFatal);
}

async function start() {
  const [draft, pending, snapshot] = await Promise.all([
    storageGet(draftKey),
    storageGet(pendingKey),
    api("snapshot"),
  ]);
  if (draft) elements["task-input"].value = draft;
  if (pending) {
    try {
      const parsed = JSON.parse(pending);
      const commands = Array.isArray(parsed) ? parsed : [parsed];
      pendingCommands = commands
        .filter((command) => typeof command?.type === "string")
        .map((command) => ({ command }));
    } catch {
      await storageRemove(pendingKey);
    }
  }
  serverState = snapshot;
  projectState();
  elements.loading.hidden = true;
  elements.app.hidden = false;
  render();
  window.setInterval(tick, 1000);
  void drainCommands();
}

function bindUi() {
  elements["add-form"].addEventListener("submit", async (event) => {
    event.preventDefault();
    const content = elements["task-input"].value.trim();
    if (!content) return;
    elements["task-input"].value = "";
    void storageRemove(draftKey);
    haptic("impactOccurred", "light");
    try {
      await sendCommand({
        type: "task.create",
        id: crypto.randomUUID(),
        content,
      });
    } catch (error) {
      if (!elements["task-input"].value) {
        elements["task-input"].value = content;
        void storageSet(draftKey, content);
      }
      showTransient(errorMessage(error));
    }
  });
  elements["task-input"].addEventListener("input", () => {
    window.clearTimeout(draftTimer);
    draftTimer = window.setTimeout(
      () => storageSet(draftKey, elements["task-input"].value),
      250,
    );
  });
  elements["task-list"].addEventListener("click", async (event) => {
    const button = event.target.closest("button[data-focus]");
    if (!button) return;
    haptic("impactOccurred", "medium");
    try {
      await sendCommand({
        type: "focus.start",
        id: crypto.randomUUID(),
        taskId: button.dataset.focus,
      });
    } catch (error) {
      showTransient(errorMessage(error));
    }
  });
  elements["task-list"].addEventListener("change", async (event) => {
    const checkbox = event.target.closest("input[data-complete]");
    if (!checkbox) return;
    const task = state.inbox.find((item) =>
      item.id === checkbox.dataset.complete
    );
    if (!task) return;
    lastCompleted = task;
    haptic("notificationOccurred", "success");
    showUndo();
    try {
      await sendCommand({
        type: "task.complete",
        id: crypto.randomUUID(),
        taskId: task.id,
      });
    } catch (error) {
      showTransient(errorMessage(error));
    }
  });
  elements["undo-button"].addEventListener("click", async () => {
    if (!lastCompleted) return;
    const task = lastCompleted;
    lastCompleted = null;
    hideToast();
    try {
      await sendCommand({
        type: "task.uncomplete",
        id: crypto.randomUUID(),
        taskId: task.id,
        optimisticTask: task,
      });
    } catch (error) {
      lastCompleted = task;
      showTransient(errorMessage(error));
    }
  });
  elements["account-button"].addEventListener("click", openSettings);
  elements["close-settings"].addEventListener("click", closeSettings);
  elements["settings-dialog"].addEventListener("close", syncBackButton);
  elements["link-account"].addEventListener("click", beginLink);
  elements["retry-button"].addEventListener("click", () => {
    elements.error.hidden = true;
    elements.loading.hidden = false;
    start().catch(showFatal);
  });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) {
      refresh().then(() => {
        render();
        void drainCommands();
      }).catch(() => {});
    }
  });
  window.addEventListener("online", () => void drainCommands());
}

function bindTelegram() {
  WebApp.onEvent?.("themeChanged", applyTheme);
  WebApp.onEvent?.("activated", () => {
    refresh().then(() => {
      render();
      void drainCommands();
    }).catch(() => {});
  });
  WebApp.SettingsButton?.onClick(openSettings);
  WebApp.SettingsButton?.show();
  WebApp.BackButton?.onClick(closeSettings);
  WebApp.MainButton?.onClick(async () => {
    const status = state.focus?.interval?.status;
    if (!status) return;
    haptic("impactOccurred", "light");
    try {
      await sendCommand({
        type: status === "paused" ? "focus.resume" : "focus.pause",
        id: crypto.randomUUID(),
      });
    } catch (error) {
      showTransient(errorMessage(error));
    }
  });
  WebApp.SecondaryButton?.onClick(async () => {
    if (!state.focus) return;
    haptic("impactOccurred", "heavy");
    try {
      await sendCommand({ type: "focus.stop", id: crypto.randomUUID() });
    } catch (error) {
      showTransient(errorMessage(error));
    }
  });
  applyTheme();
}

async function refresh() {
  const generation = serverGeneration;
  const snapshot = await api("snapshot");
  if (generation !== serverGeneration) return;
  serverState = snapshot;
  projectState();
}

function sendCommand(command) {
  const queued = {
    ...command,
    optimisticAt: new Date().toISOString(),
  };
  return new Promise((resolve, reject) => {
    const pending = { command: queued, resolve, reject };
    pendingCommands.push(pending);
    pending.persisted = persistPending();
    projectState();
    render();
    void drainCommands();
  });
}

async function drainCommands() {
  if (busy) return;
  busy = true;
  try {
    while (pendingCommands.length > 0) {
      const pending = pendingCommands[0];
      await pending.persisted;
      const { optimisticAt: _, optimisticTask: __, ...command } =
        pending.command;
      try {
        serverState = await api("command", { command });
        serverGeneration += 1;
      } catch (error) {
        if (error.retryable !== false) break;
        pendingCommands.shift();
        await persistPending();
        projectState();
        render();
        pending.reject?.(error);
        continue;
      }
      pendingCommands.shift();
      await persistPending();
      projectState();
      render();
      pending.resolve?.(serverState);
    }
  } finally {
    busy = false;
  }
}

function projectState() {
  state = pendingCommands.reduce(
    (current, pending) => applyOptimisticCommand(current, pending.command),
    serverState,
  );
}

function persistPending() {
  if (pendingCommands.length === 0) {
    return storageRemove(pendingKey);
  }
  return storageSet(
    pendingKey,
    JSON.stringify(pendingCommands.map((pending) => pending.command)),
  );
}

async function api(action, extra = {}) {
  if (!telegramContext) throw new Error("telegram_context_required");
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      apikey: config.supabaseAnonKey ?? "",
      "X-Telegram-Init-Data": WebApp.initData,
    },
    body: JSON.stringify({ action, ...extra }),
  });
  const payload = await response.json().catch(() => ({
    ok: false,
    code: "invalid_response",
  }));
  if (!response.ok || payload.ok !== true) {
    const error = new Error(payload.code ?? "request_failed");
    error.retryable = payload.code === "retry_later" ||
      response.status === 401 || response.status === 429 ||
      response.status >= 500;
    throw error;
  }
  return payload.data;
}

function render() {
  elements.app.hidden = false;
  elements.error.hidden = true;
  elements.empty.hidden = state.inbox.length !== 0;
  elements["task-list"].replaceChildren(
    ...state.inbox.map((task) => {
      const item = document.createElement("li");
      item.className = "task";
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.dataset.complete = task.id;
      checkbox.setAttribute("aria-label", `${text.completed}: ${task.content}`);
      const title = document.createElement("span");
      title.className = "task-title";
      title.textContent = task.content;
      const focus = document.createElement("button");
      focus.type = "button";
      focus.className = "focus-button";
      focus.dataset.focus = task.id;
      focus.textContent = text.focus;
      focus.disabled = Boolean(state.focus);
      item.append(checkbox, title, focus);
      return item;
    }),
  );
  const active = Boolean(state.focus);
  elements["focus-card"].hidden = !active;
  if (active) {
    const task = state.inbox.find((item) => item.id === state.focus.run.taskId);
    elements["focus-task"].textContent = task?.content ?? text.focus;
    tick();
  }
  elements["account-status"].textContent = state.account.linked
    ? text.linked
    : text.guest;
  elements["link-account"].hidden = state.account.linked;
  updateButtons();
}

function tick() {
  if (!state.focus) return;
  const seconds = remainingSeconds(state.focus);
  elements["focus-clock"].textContent = formatClock(seconds);
  if (seconds === 0 && !autoCompleting) {
    autoCompleting = true;
    sendCommand({ type: "focus.complete", id: crypto.randomUUID() })
      .then(() => haptic("notificationOccurred", "success"))
      .catch((error) => showTransient(errorMessage(error)))
      .finally(() => {
        autoCompleting = false;
      });
  }
}

function updateButtons() {
  const main = WebApp?.MainButton;
  const secondary = WebApp?.SecondaryButton;
  if (!state.focus) {
    main?.hide();
    secondary?.hide();
    return;
  }
  main?.setText(
    state.focus.interval.status === "paused" ? text.resume : text.pause,
  );
  main?.show();
  secondary?.setText(text.stop);
  secondary?.show();
  main?.enable();
  secondary?.enable();
  main?.hideProgress();
}

function openSettings() {
  if (!elements["settings-dialog"].open) {
    elements["settings-dialog"].showModal();
  }
  syncBackButton();
}

function closeSettings() {
  if (elements["settings-dialog"].open) elements["settings-dialog"].close();
  syncBackButton();
}

function syncBackButton() {
  if (elements["settings-dialog"].open) WebApp?.BackButton?.show();
  else WebApp?.BackButton?.hide();
}

async function beginLink() {
  if (busy || pendingCommands.length > 0) return;
  elements["link-account"].disabled = true;
  elements["link-account"].textContent = text.opening;
  try {
    const result = await api("begin_link");
    WebApp.openLink(result.url, { try_instant_view: false });
  } catch (error) {
    showTransient(errorMessage(error));
  } finally {
    elements["link-account"].disabled = false;
    elements["link-account"].textContent = text.signIn;
  }
}

function applyText() {
  elements["outside-title"].textContent = text.outsideTitle;
  elements["outside-body"].textContent = text.outsideBody;
  elements["open-bot"].textContent = text.openBot.replace(
    "pomodoist_bot",
    botName,
  );
  elements["open-bot"].href = `https://t.me/${botName}?startapp`;
  elements["loading-text"].textContent = text.loading;
  elements["inbox-title"].textContent = text.inbox;
  elements["task-label"].textContent = text.addPlaceholder;
  elements["task-input"].placeholder = text.addPlaceholder;
  elements["add-button"].textContent = text.add;
  elements.empty.textContent = text.empty;
  elements["settings-title"].textContent = text.settings;
  elements["link-account"].textContent = text.signIn;
  elements["undo-button"].textContent = text.undo;
  elements["retry-button"].textContent = text.retry;
  elements["account-button"].setAttribute("aria-label", text.settings);
  elements["close-settings"].setAttribute("aria-label", text.close);
}

function applyTheme() {
  document.documentElement.style.colorScheme = WebApp?.colorScheme ?? "light";
  WebApp?.setHeaderColor?.("bg_color");
  WebApp?.setBackgroundColor?.("bg_color");
  WebApp?.setBottomBarColor?.("bottom_bar_bg_color");
}

function showUndo() {
  window.clearTimeout(toastTimer);
  elements["toast-text"].textContent = text.completed;
  elements["undo-button"].hidden = false;
  elements.toast.hidden = false;
  toastTimer = window.setTimeout(hideToast, 8000);
}

function showTransient(message) {
  window.clearTimeout(toastTimer);
  elements["toast-text"].textContent = message;
  elements["undo-button"].hidden = true;
  elements.toast.hidden = false;
  toastTimer = window.setTimeout(hideToast, 5000);
}

function hideToast() {
  elements.toast.hidden = true;
}

function showFatal(error) {
  elements.loading.hidden = true;
  elements.app.hidden = true;
  elements.error.hidden = false;
  elements["error-text"].textContent = errorMessage(error);
}

function errorMessage(error) {
  if (error?.message === "link_conflict") return text.linkConflict;
  if (error?.message === "link_expired") return text.linkExpired;
  return text.error;
}

function haptic(method, value) {
  try {
    WebApp?.HapticFeedback?.[method]?.(value);
  } catch {
    // Haptics are optional on Telegram Desktop/Web.
  }
}

function storageGet(key) {
  const local = localStorage.getItem(key);
  return local == null ? storageCall("getItem", key) : Promise.resolve(local);
}

async function storageSet(key, value) {
  localStorage.setItem(key, value);
  storageWrites = storageWrites.then(() => storageCall("setItem", key, value));
  await storageWrites;
}

async function storageRemove(key) {
  localStorage.removeItem(key);
  storageWrites = storageWrites.then(() => storageCall("removeItem", key));
  await storageWrites;
}

function storageCall(method, ...args) {
  const DeviceStorage = WebApp?.DeviceStorage;
  if (typeof DeviceStorage?.[method] !== "function") {
    return Promise.resolve(null);
  }
  return new Promise((resolve) => {
    let settled = false;
    const done = (error, value) => {
      if (settled) return;
      settled = true;
      resolve(error == null ? value ?? null : null);
    };
    try {
      const result = DeviceStorage[method](...args, done);
      if (result?.then) {
        result.then((value) => done(null, value), () => done("error"));
      }
      window.setTimeout(() => done("timeout"), 1500);
    } catch {
      done("error");
    }
  });
}
