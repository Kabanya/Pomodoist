import {
  applyOptimisticCommand,
  formatClock,
  localeFor,
  remainingSeconds,
  scheduleFor,
  taskPatch,
  textFor,
} from "./core.js";

const config = window.pomodoistRuntimeConfig ?? {};
const WebApp = window.Telegram?.WebApp;
const telegramContext = typeof WebApp?.initData === "string" &&
  WebApp.initData.length > 0;
const locale = localeFor(
  telegramContext
    ? WebApp.initDataUnsafe?.user?.language_code ?? "en"
    : navigator.language,
);
const text = textFor(locale);
const endpoint = `${config.supabaseUrl ?? ""}/functions/v1/pomodoist-telegram`;
const botName = config.environment === "staging"
  ? "pomodoist_test_bot"
  : "pomodoist_bot";
const draftKey = "pomodoist.telegram.draft.v1";
const pendingKey = "pomodoist.telegram.pending.v1";
const elements = Object.fromEntries(
  [...document.querySelectorAll("[id]")].map(
    (element) => [element.id, element],
  ),
);
const timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
let state = { account: { linked: false }, inbox: [], tasks: [], focus: null };
let serverState = state;
let pendingCommands = [];
let view = "inbox", page = 0, selectedId = null, editingTask = null;
let routeGeneration = 0, serverGeneration = 0, snapshotRequest = 0;
let snapshotsInFlight = 0, lastUpdatedAt = null, refreshFailed = false;
let busy = false,
  loadingRoute = false,
  detailBusy = false,
  autoCompleting = false;
let lastCompleted = null, toastTimer, draftTimer, clockTimer, refreshTimer;
let storageWrites = Promise.resolve();

document.documentElement.lang = locale;
document.documentElement.dir = text.direction;
applyText();
applyTheme();
if (!telegramContext) {
  elements.loading.hidden = true;
  elements.outside.hidden = false;
} else {
  WebApp.ready();
  WebApp.expand();
  bindUi();
  WebApp.onEvent?.("themeChanged", applyTheme);
  WebApp.onEvent?.("activated", refreshInBackground);
  WebApp.SettingsButton?.onClick(openSettings);
  WebApp.SettingsButton?.show();
  WebApp.BackButton?.onClick(goBack);
  // Controls live in the Mini App and remain available on every Telegram client.
  WebApp.MainButton?.hide();
  WebApp.SecondaryButton?.hide();
  start().catch(showFatal);
}

function query() {
  return {
    view: view === "focus" ? "inbox" : view,
    page,
    timeZone,
    ...(selectedId ? { taskId: selectedId } : {}),
  };
}

async function start() {
  const [draft, pending, snapshot] = await Promise.all([
    storageGet(draftKey),
    storageGet(pendingKey),
    api("snapshot", query()),
  ]);
  if (draft) elements["task-input"].value = draft;
  if (pending) {
    try {
      const parsed = JSON.parse(pending);
      pendingCommands = (Array.isArray(parsed) ? parsed : [parsed])
        .filter((command) => typeof command?.type === "string").map(
          (command) => ({ command }),
        );
    } catch {
      await storageRemove(pendingKey);
    }
  }
  serverState = snapshot;
  lastUpdatedAt = new Date();
  refreshFailed = false;
  projectState();
  elements.loading.hidden = true;
  elements.app.hidden = false;
  render();
  if (!clockTimer) clockTimer = window.setInterval(tick, 1000);
  if (!refreshTimer) refreshTimer = window.setInterval(refreshInBackground, 5000);
  void drainCommands();
}

function bindUi() {
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.addEventListener("click", () => navigate(button.dataset.view));
  });
  elements["previous-page"].addEventListener(
    "click",
    () => navigate(view, page - 1),
  );
  elements["next-page"].addEventListener(
    "click",
    () => navigate(view, page + 1),
  );
  elements["refresh-button"].addEventListener("click", refreshUi);
  elements["add-form"].addEventListener("submit", async (event) => {
    event.preventDefault();
    const content = elements["task-input"].value.trim();
    if (!content) return;
    window.clearTimeout(draftTimer);
    elements["task-input"].value = "";
    void storageRemove(draftKey);
    haptic("impactOccurred", "light");
    try {
      await sendCommand({ type: "task.create", content });
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
  elements["task-list"].addEventListener("click", (event) => {
    const button = event.target.closest("button[data-task]");
    if (button) void openTask(button.dataset.task);
  });
  elements["task-list"].addEventListener("change", (event) => {
    const checkbox = event.target.closest("input[data-complete]");
    const task = state.tasks.find((item) =>
      item.id === checkbox?.dataset.complete
    );
    if (task) void completeTask(task);
  });
  elements["undo-button"].addEventListener("click", async () => {
    if (!lastCompleted) return;
    const task = lastCompleted;
    lastCompleted = null;
    hideToast();
    try {
      await sendCommand({
        type: "task.uncomplete",
        taskId: task.id,
        optimisticTask: task,
      });
    } catch (error) {
      showTransient(errorMessage(error));
    }
  });
  elements["account-button"].addEventListener("click", openSettings);
  elements["close-settings"].addEventListener(
    "click",
    () => elements["settings-dialog"].close(),
  );
  elements["settings-dialog"].addEventListener("close", syncBackButton);
  elements["link-account"].addEventListener("click", beginLink);
  elements["open-app"].addEventListener("click", openApp);
  elements["detail-open-app"].addEventListener("click", openApp);
  elements["close-task"].addEventListener(
    "click",
    () => elements["task-dialog"].close(),
  );
  elements["task-dialog"].addEventListener("close", () => {
    selectedId = null;
    editingTask = null;
    routeGeneration++;
    syncBackButton();
  });
  elements["edit-form"].addEventListener("input", saveDetailDraft);
  elements["edit-form"].addEventListener("submit", saveTask);
  elements["complete-task"].addEventListener(
    "click",
    () => void completeTask(state.task),
  );
  elements["start-focus"].addEventListener("click", () => {
    const task = state.task;
    if (!task || state.focus) return;
    elements["task-dialog"].close();
    void navigate("focus");
    void runCommand({ type: "focus.start", taskId: task.id });
  });
  elements["focus-start"].addEventListener("click", () => {
    if (state.focus) return;
    haptic("impactOccurred", "light");
    void runCommand({ type: "focus.start" });
  });
  elements["focus-toggle"].addEventListener(
    "click",
    () =>
      focusCommand(
        state.focus?.interval.status === "paused" ? "resume" : "pause",
      ),
  );
  elements["focus-stop"].addEventListener("click", () => focusCommand("stop"));
  elements["focus-finish"].addEventListener(
    "click",
    () => focusCommand("complete"),
  );
  elements["refresh-task"].addEventListener("click", async () => {
    const id = selectedId;
    if (await refreshUi() && selectedId === id && state.task) {
      fillDetail(state.task, true);
    }
  });
  elements["delete-task"].addEventListener("click", () => {
    elements["delete-confirmation"].hidden = false;
  });
  elements["cancel-delete"].addEventListener("click", () => {
    elements["delete-confirmation"].hidden = true;
  });
  elements["confirm-delete"].addEventListener("click", async () => {
    const task = state.task;
    if (!task) return;
    setDetailBusy(true);
    try {
      await sendCommand({
        type: "task.delete",
        taskId: task.id,
        expectedRevision: task.revision,
      });
      if (selectedId === task.id) elements["task-dialog"].close();
    } catch (error) {
      showDetailError(error, task.id);
    } finally {
      setDetailBusy(false);
    }
  });
  elements["retry-button"].addEventListener("click", () => {
    elements.error.hidden = true;
    elements.loading.hidden = false;
    start().catch(showFatal);
  });
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) refreshInBackground();
  });
  window.addEventListener("online", refreshInBackground);
  window.addEventListener("offline", render);
}

async function navigate(nextView, nextPage = 0) {
  view = nextView;
  page = Math.max(0, nextPage);
  routeGeneration++;
  loadingRoute = true;
  render();
  syncBackButton();
  await refreshUi();
}

async function refreshSnapshot() {
  const route = routeGeneration,
    generation = serverGeneration,
    request = ++snapshotRequest;
  const isCurrent = () => route === routeGeneration &&
    generation === serverGeneration && request === snapshotRequest;
  snapshotsInFlight++;
  try {
    const snapshot = await api("snapshot", query());
    if (!isCurrent()) return false;
    serverState = snapshot;
    lastUpdatedAt = new Date();
    refreshFailed = false;
    page = snapshot.page ?? page;
    loadingRoute = false;
    projectState();
    render();
    return true;
  } catch (error) {
    if (!isCurrent()) return false;
    refreshFailed = true;
    renderSyncStatus();
    throw error;
  } finally {
    snapshotsInFlight--;
  }
}

function refreshInBackground() {
  if (elements.app.hidden || document.hidden || WebApp?.isActive === false ||
    !navigator.onLine || busy || detailBusy || snapshotsInFlight) return;
  void refreshUi(true);
}

async function refreshUi(background = false) {
  try {
    const updated = await refreshSnapshot();
    void drainCommands();
    return updated;
  } catch (error) {
    if (background !== true) showTransient(errorMessage(error));
    return false;
  }
}

function sendCommand(command) {
  const queued = {
    ...command,
    id: command.id ?? crypto.randomUUID(),
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

async function runCommand(command) {
  try {
    await sendCommand(command);
    return true;
  } catch (error) {
    showTransient(errorMessage(error));
    return false;
  }
}

async function drainCommands() {
  if (busy) return;
  busy = true;
  try {
    while (pendingCommands.length) {
      const pending = pendingCommands[0];
      const route = routeGeneration;
      const request = snapshotRequest;
      const { optimisticAt: _, optimisticTask: __, ...command } =
        pending.command;
      let snapshot;
      try {
        await pending.persisted;
      } catch (error) {
        // A command that could not be saved must not enter the network queue.
        pendingCommands.shift();
        projectState();
        pending.reject?.(error);
        if (!pending.reject) showTransient(errorMessage(error));
        continue;
      }
      try {
        snapshot = await api("command", { ...query(), command });
        serverGeneration++;
      } catch (error) {
        if (error.retryable !== false) {
          showTransient(errorMessage(error));
          break;
        }
        pendingCommands.shift();
        await persistPending().catch(() => {});
        projectState();
        render();
        pending.reject?.(error);
        if (!pending.reject) showTransient(errorMessage(error));
        continue;
      }
      pendingCommands.shift();
      // If cleanup fails, the persisted command can safely replay its receipt.
      await persistPending().catch(() => {});
      if (!pendingCommands.length && elements["undo-button"].hidden) {
        hideToast();
      }
      if (["task.update", "task.delete"].includes(command.type)) {
        localStorage.removeItem(detailDraftKey(command.taskId));
      }
      if (route === routeGeneration && request === snapshotRequest) {
        if (selectedId && snapshot.task?.id !== selectedId) {
          snapshot.task = serverState.task;
        }
        serverState = snapshot;
        lastUpdatedAt = new Date();
        refreshFailed = false;
        page = snapshot.page ?? page;
        loadingRoute = false;
        projectState();
        render();
      } else {
        // Navigation or a newer snapshot superseded this command response.
        await refreshSnapshot().catch(() => {});
      }
      pending.resolve?.(snapshot);
    }
  } catch (error) {
    showTransient(errorMessage(error));
  } finally {
    busy = false;
    render();
  }
}

function projectState() {
  state = pendingCommands.reduce(
    (current, pending) => applyOptimisticCommand(current, pending.command),
    serverState,
  );
}

function persistPending() {
  return pendingCommands.length
    ? storageSet(
      pendingKey,
      JSON.stringify(pendingCommands.map((pending) => pending.command)),
    )
    : storageRemove(pendingKey);
}

async function api(action, extra = {}) {
  if (!telegramContext) throw new Error("telegram_context_required");
  const response = await fetch(endpoint, {
    method: "POST",
    signal: AbortSignal.timeout(15000),
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
  if (elements.app.hidden) return;
  const focusView = view === "focus";
  elements["inbox-title"].textContent = view === "completed"
    ? text.completedView
    : text[view];
  elements["view-meta"].textContent = focusView
    ? text.focusHint
    : `${text.taskCount}: ${
      loadingRoute ? "…" : state.total ?? 0
    } · ${timeZone}`;
  document.querySelectorAll(".navigation [data-view]").forEach((button) => {
    button.setAttribute(
      "aria-current",
      button.dataset.view === view ? "page" : "false",
    );
  });
  elements["add-form"].hidden = focusView || view === "completed";
  elements["task-list"].hidden = focusView || loadingRoute;
  elements.empty.hidden = focusView || !loadingRoute && state.tasks.length > 0;
  elements.empty.textContent = loadingRoute
    ? text.loading
    : view === "inbox"
    ? text.empty
    : text.emptyView;
  if (!loadingRoute && !focusView) {
    elements["task-list"].replaceChildren(...state.tasks.map((task) => {
      const item = document.createElement("li");
      item.className = `task${
        task.status === "completed" ? " is-completed" : ""
      }`;
      item.style.setProperty("--priority", `var(--p${task.priority ?? 4})`);
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.checked = task.status === "completed";
      checkbox.dataset.complete = task.id;
      checkbox.disabled = pendingCommands.some((p) =>
        p.command.taskId === task.id
      );
      checkbox.setAttribute(
        "aria-label",
        `${checkbox.checked ? text.restore : text.complete}: ${task.content}`,
      );
      const button = document.createElement("button");
      button.type = "button";
      button.className = "task-content";
      button.dataset.task = task.id;
      const title = document.createElement("span");
      title.className = "task-title";
      title.textContent = task.content;
      const meta = document.createElement("span");
      meta.className = "task-meta";
      meta.textContent = [
        task.projectId === "inbox" ? "" : task.projectName,
        scheduleLabel(task),
        task.priority < 4 ? `P${task.priority}` : "",
        task.id === state.focus?.run.taskId ? text.focus : "",
      ].filter(Boolean).join(" · ");
      button.append(title, meta);
      const completion = document.createElement("label");
      completion.className = "task-check";
      completion.append(checkbox);
      item.append(completion, button);
      return item;
    }));
  }
  elements["pagination"].hidden = focusView || loadingRoute ||
    (state.pages ?? 1) < 2;
  elements["previous-page"].disabled = page === 0;
  elements["next-page"].disabled = page >= (state.pages ?? 1) - 1;
  elements["page-number"].textContent = `${page + 1} / ${state.pages ?? 1}`;
  elements["focus-card"].hidden = !state.focus;
  elements["focus-card"].classList.toggle("compact", !focusView);
  elements["focus-empty"].hidden = !focusView || Boolean(state.focus) ||
    loadingRoute;
  const focusTask = state.focusTask ??
    state.inbox.find((task) => task.id === state.focus?.run.taskId);
  elements["focus-task"].textContent = focusTask?.content ?? text.focus;
  elements["focus-toggle"].textContent =
    state.focus?.interval.status === "paused" ? text.resume : text.pause;
  elements["focus-status"].textContent =
    state.focus?.interval.status === "paused" ? text.paused : text.focusing;
  renderSyncStatus();
  elements["account-status"].textContent = state.account.linked
    ? text.linked
    : text.guest;
  elements["link-account"].hidden = state.account.linked;
  elements["link-account"].disabled = busy || pendingCommands.length > 0;
  updateDetailActions();
  tick();
}

function renderSyncStatus() {
  const messages = [];
  if (!navigator.onLine) messages.push(text.offline);
  if (pendingCommands.length) messages.push(text.pending);
  if (navigator.onLine && refreshFailed) messages.push(text.refreshFailed);
  if (lastUpdatedAt) {
    const time = new Intl.DateTimeFormat(locale, {
      hour: "2-digit", minute: "2-digit", second: "2-digit", timeZone,
    }).format(lastUpdatedAt);
    messages.push(text.updatedAt.replace("{time}", time));
  }
  elements["sync-status"].textContent = messages.join(" ");
}

function scheduleLabel(task) {
  try {
    const schedule = scheduleFor(task.dueJson);
    if (!task.day) return "";
    const date = new Intl.DateTimeFormat(locale, {
      month: "short",
      day: "numeric",
      timeZone: "UTC",
    }).format(new Date(`${task.day}T12:00:00Z`));
    if (schedule.type !== "timed") return date;
    const clock = (value) =>
      new Intl.DateTimeFormat(locale, {
        timeZone,
        hour: "2-digit",
        minute: "2-digit",
      }).format(new Date(value));
    const endDay = new Intl.DateTimeFormat(locale, {
      timeZone,
      month: "short",
      day: "numeric",
    }).format(new Date(schedule.end));
    const startDay = new Intl.DateTimeFormat(locale, {
      timeZone,
      month: "short",
      day: "numeric",
    }).format(new Date(schedule.start));
    return `${date} ${clock(schedule.start)}–${
      endDay === startDay ? "" : endDay + " "
    }${clock(schedule.end)}`;
  } catch {
    return text.noDate;
  }
}

function tick() {
  if (!state.focus) return;
  const seconds = remainingSeconds(state.focus);
  elements["focus-clock"].textContent = formatClock(seconds);
  elements["focus-finish"].hidden = seconds > 0;
  if (seconds === 0 && !autoCompleting && !pendingCommands.length) {
    autoCompleting = true;
    // The server remains authoritative if the device clock runs ahead.
    void focusCommand("complete").finally(() =>
      window.setTimeout(() => {
        autoCompleting = false;
      }, 5000)
    );
  }
}

async function focusCommand(action) {
  if (!state.focus) return;
  haptic("impactOccurred", "light");
  await runCommand({
    type: `focus.${action}`,
    runId: state.focus.run.id,
    intervalId: state.focus.interval.id,
  });
}

async function completeTask(task) {
  if (!task) return;
  const completing = task.status !== "completed";
  if (completing) {
    lastCompleted = task;
    showUndo();
  }
  haptic("notificationOccurred", "success");
  const ok = await runCommand({
    type: completing ? "task.complete" : "task.uncomplete",
    taskId: task.id,
    expectedRevision: task.revision,
    optimisticTask: task,
  });
  if (ok && selectedId === task.id) {
    elements["task-dialog"].close();
    if (completing) showUndo();
  }
}

async function openTask(id) {
  selectedId = id;
  editingTask = null;
  routeGeneration++;
  elements["detail-meta"].textContent = text.loading;
  elements["edit-form"].reset();
  elements["detail-error"].hidden = true;
  elements["delete-confirmation"].hidden = true;
  elements["task-dialog"].showModal();
  setDetailBusy(true);
  syncBackButton();
  try {
    if (!await refreshSnapshot() || selectedId !== id) return;
    if (!state.task) throw new Error("task_not_found");
    fillDetail(state.task);
  } catch (error) {
    showDetailError(error, id);
  } finally {
    if (selectedId === id) setDetailBusy(false);
  }
}

function detailDraftKey(id) {
  return `pomodoist.telegram.task-draft.v1.${id}`;
}
function detailFields() {
  return {
    content: elements["edit-title"].value,
    description: elements["edit-note"].value,
    date: elements["edit-date"].value,
    priority: Number(elements["edit-priority"].value),
  };
}
function saveDetailDraft() {
  if (editingTask) {
    localStorage.setItem(
      detailDraftKey(editingTask.id),
      JSON.stringify({ task: editingTask, fields: detailFields() }),
    );
  }
}
function fillDetail(task, refresh = false) {
  let draft;
  try {
    draft = JSON.parse(localStorage.getItem(detailDraftKey(task.id)));
  } catch { /* Ignore an unreadable draft. */ }
  editingTask = refresh ? task : draft?.task ?? task;
  const fieldsOf = (item) => ({
    content: item.content,
    description: item.description ?? "",
    date: item.day ?? "",
    priority: item.priority,
  });
  const fields = fieldsOf(task);
  if (draft?.fields && draft.task) {
    const previous = fieldsOf(draft.task);
    for (const key of Object.keys(fields)) {
      if (!refresh || draft.fields[key] !== previous[key]) {
        fields[key] = draft.fields[key];
      }
    }
  }
  elements["edit-title"].value = fields.content;
  elements["edit-note"].value = fields.description;
  elements["edit-date"].value = fields.date;
  elements["edit-priority"].value = fields.priority;
  elements["detail-error"].hidden = true;
  const schedule = scheduleFor(task.dueJson);
  elements["edit-date"].required = Boolean(schedule.recurrence);
  elements["schedule-hint"].textContent = [
    schedule.type === "timed" ? text.timedHint : "",
    schedule.recurrence ? text.recurringHint : "",
  ].filter(Boolean).join(" ");
  const deadline = scheduleFor(task.deadlineJson);
  elements["detail-extra"].textContent = [
    deadline.type === "date"
      ? `${text.deadline}: ${String(deadline.date).slice(0, 10)}`
      : "",
    schedule.recurrence || schedule.recurrenceSeriesId ? text.repeat : "",
  ].filter(Boolean).join(" · ");
  if (refresh && draft) saveDetailDraft();
  updateDetailActions();
}
function updateDetailActions() {
  if (!selectedId) return;
  const task = state.task?.id === selectedId ? state.task : null;
  const pending = pendingCommands.some((p) => p.command.taskId === selectedId);
  elements["edit-form"].querySelectorAll("input, textarea, select").forEach(
    (input) => {
      input.disabled = detailBusy || pending || !editingTask;
    },
  );
  elements["complete-task"].textContent = task?.status === "completed"
    ? text.restore
    : text.complete;
  elements["start-focus"].hidden = task?.status === "completed";
  for (
    const id of [
      "complete-task",
      "start-focus",
      "delete-task",
      "confirm-delete",
      "save-task",
    ]
  ) {
    elements[id].disabled = !task || !editingTask || detailBusy || pending ||
      id === "start-focus" && Boolean(state.focus);
  }
  if (task) {
    elements["detail-meta"].textContent = [
      task.projectId === "inbox" ? text.inbox : task.projectName,
      task.status === "completed" ? text.done : text.open,
      scheduleLabel(task) || text.noDate,
    ].filter(Boolean).join(" · ");
  }
}
function setDetailBusy(value) {
  detailBusy = value;
  elements["edit-form"].querySelectorAll("input, textarea, select").forEach(
    (input) => {
      input.disabled = value;
    },
  );
  elements["save-task"].textContent = value ? text.saving : text.save;
  updateDetailActions();
}
async function saveTask(event) {
  event.preventDefault();
  if (!editingTask) return;
  const task = editingTask;
  const patch = taskPatch(task, detailFields());
  if (!elements["edit-title"].value.trim()) {
    elements["edit-title"].focus();
    return;
  }
  if (!Object.keys(patch).length) {
    elements["task-dialog"].close();
    return;
  }
  saveDetailDraft();
  setDetailBusy(true);
  try {
    await sendCommand({
      type: "task.update",
      taskId: task.id,
      expectedRevision: task.revision,
      patch,
    });
    if (selectedId === task.id) elements["task-dialog"].close();
  } catch (error) {
    showDetailError(error, task.id);
  } finally {
    if (selectedId === task.id) setDetailBusy(false);
  }
}
function showDetailError(error, id) {
  if (selectedId !== id) {
    showTransient(errorMessage(error));
    return;
  }
  elements["detail-error"].textContent = errorMessage(error);
  elements["detail-error"].hidden = false;
}

function openSettings() {
  elements["account-error"].hidden = true;
  if (!elements["settings-dialog"].open) {
    elements["settings-dialog"].showModal();
  }
  syncBackButton();
}
function goBack() {
  if (elements["settings-dialog"].open) elements["settings-dialog"].close();
  else if (elements["task-dialog"].open) elements["task-dialog"].close();
  else void navigate("inbox");
}
function syncBackButton() {
  if (
    elements["settings-dialog"].open || elements["task-dialog"].open ||
    view !== "inbox"
  ) WebApp?.BackButton?.show();
  else WebApp?.BackButton?.hide();
}
function openApp() {
  WebApp.openLink(new URL("/", window.location.href).href, {
    try_instant_view: false,
  });
}
async function beginLink() {
  if (busy || pendingCommands.length) return;
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
  document.querySelectorAll("[data-text]").forEach((element) => {
    element.textContent = text[element.dataset.text];
  });
  document.querySelectorAll("[data-label]").forEach((element) => {
    element.setAttribute("aria-label", text[element.dataset.label]);
  });
  for (
    const [id, key] of Object.entries({
      "outside-title": "outsideTitle",
      "outside-body": "outsideBody",
      "loading-text": "loading",
      "task-label": "addPlaceholder",
      "add-button": "add",
      "settings-title": "settings",
      "link-account": "signIn",
      "undo-button": "undo",
      "retry-button": "retry",
    })
  ) elements[id].textContent = text[key];
  elements["open-bot"].textContent = text.openBot.replace(
    "pomodoist_bot",
    botName,
  );
  elements["open-bot"].href = `https://t.me/${botName}?startapp`;
  elements["task-input"].placeholder = text.addPlaceholder;
  elements["account-button"].setAttribute("aria-label", text.settings);
  elements["close-settings"].setAttribute("aria-label", text.close);
}
function applyTheme() {
  const scheme = WebApp?.colorScheme ??
    (window.matchMedia("(prefers-color-scheme: dark)").matches
      ? "dark"
      : "light");
  document.documentElement.dataset.theme = scheme;
  document.documentElement.style.colorScheme = scheme;
  const style = getComputedStyle(document.documentElement);
  WebApp?.setHeaderColor?.(style.getPropertyValue("--canvas").trim());
  WebApp?.setBackgroundColor?.(style.getPropertyValue("--canvas").trim());
  if (WebApp?.isVersionAtLeast?.("7.10")) {
    WebApp.setBottomBarColor?.(style.getPropertyValue("--surface").trim());
  }
}
function showUndo() {
  showTransient(text.completed);
  elements["undo-button"].hidden = false;
}
function showTransient(message) {
  window.clearTimeout(toastTimer);
  elements["toast-text"].textContent = message;
  elements["undo-button"].hidden = true;
  // The top-layer dialog needs its own error region; a toast behind it is invisible.
  if (elements["task-dialog"].open) {
    elements["detail-error"].textContent = message;
    elements["detail-error"].hidden = false;
  } else if (elements["settings-dialog"].open) {
    elements["account-error"].textContent = message;
    elements["account-error"].hidden = false;
  } else {
    elements.toast.hidden = false;
    toastTimer = window.setTimeout(hideToast, 8000);
  }
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
  return ({
    link_conflict: text.linkConflict,
    link_expired: text.linkExpired,
    task_changed: text.changed,
    task_not_found: text.notFound,
    recurring_task_requires_app: text.requiresApp,
    task_batch_too_large: text.requiresApp,
    task_has_active_focus: text.activeFocus,
    focus_changed: text.focusChanged,
    focus_already_active: text.focusChanged,
    focus_not_elapsed: text.notElapsed,
    expired_init_data: text.expired,
    invalid_init_data: text.expired,
  })[error?.message] ?? (navigator.onLine ? text.error : text.offline);
}
function haptic(method, value) {
  try {
    WebApp?.HapticFeedback?.[method]?.(value);
  } catch { /* Optional on desktop. */ }
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
