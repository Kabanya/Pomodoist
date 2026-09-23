import { text, localize } from './i18n.js';
import { config } from './config.js';
import { dateKey, deleteConfirmation, dueDay, openSubtasks, parseDue, schedule, scheduleFields, tabDraft, tasksFor } from './core.js';
import { DEFAULT_MINUTES, PRESETS, initial, phaseDuration, reduce, remainingMs } from './timer.js';
import { Realtime } from './realtime.js';
localize(document);
const $ = id => document.getElementById(id);
let state, view = 'today', editing = null, dirty = new Set(), busy = 0, live = false, syncing = false;
let owner = null, poll, hintTimer, refreshAgain = false;
let timer = initial(), timerTick = null;
const realtime = new Realtime(() => call('realtime'), () => {
  clearTimeout(hintTimer); hintTimer = setTimeout(refresh, 150);
}, connected => { live = connected; status(); });
$('open-app').href = config.webUrl;
async function call(type, payload = {}) {
  const result = await chrome.runtime.sendMessage({ type, payload });
  if (!result?.ok) throw new Error(result?.error || text("The extension did not respond. Reopen it and retry."));
  return result.value;
}
function error(message = '') { $('error').textContent = text(message); $('error').hidden = !message; }
function lock() {
  for (const element of document.querySelectorAll('button,input,select,textarea')) element.disabled = busy > 0;
}
async function run(action) {
  busy++; lock(); error('');
  try { await action(); } catch (e) { error(e.message); }
  finally { busy--; lock(); }
}
function status() {
  if (!state?.user) return;
  const pending = state.pending;
  $('connection').textContent = pending ? text('{count} changes saved locally · waiting to sync', { count: pending }) : syncing ? text("Syncing…") :
    state.error ? text("Offline or sync needs attention") : state.lastSyncedAt ? (live ? text("Live sync") : text("Synced · periodic refresh")) : text("Loading account data…");
  const overview = state.overview, profile = overview?.profile;
  const app = overview?.apps?.find(item => (item.id ?? item.appId ?? item.app_id) === 'pomodoist');
  let plan = text("Plan unavailable");
  if (profile) {
    const active = app?.entitlements?.some(item => item.status === 'active' &&
      (!(item.validUntil ?? item.valid_until) || new Date(item.validUntil ?? item.valid_until).getTime() > Date.now()));
    plan = (profile.pomodoistIsPro ?? profile.pomodoist_is_pro) ? text("Pro") : active ? text("Account access active") : text("Free");
    if (Date.now() - state.overviewAt > 90000) plan += text(" (cached)");
  }
  $('account').textContent = `${state.user.email} · ${plan}`;
  $('account').title = state.overviewAt ? text('Account status checked {time}', { time: new Date(state.overviewAt).toLocaleString() }) : text("Account status has not been loaded.");
}
function render(next) {
  const previousOwner = owner;
  state = next; owner = state.user?.id ?? null;
  $('startup').hidden = true; $('auth').hidden = !!owner; $('app').hidden = !owner;
  $('clear-account').hidden = !!owner || !state.pending;
  if (previousOwner !== owner) {
    editing = null; $('editor').hidden = true; showPanel();
    $('new-title').value = '';
    realtime.stop(); clearInterval(poll);
    if (owner) { realtime.start(); poll = setInterval(refresh, 30000); }
  }
  error(state.error);
  if (!owner) return;
  status();
  const scroll = $('task-scroll').scrollTop;
  const focusId = document.activeElement?.dataset.taskId;
  const rows = tasksFor(state.records, view);
  const fragment = document.createDocumentFragment();
  for (const task of rows) {
    const li = document.createElement('li'); li.className = `task${task.status === 'completed' ? ' completed' : ''}`;
    const check = document.createElement('input'); check.type = 'checkbox'; check.checked = task.status === 'completed';
    check.disabled = busy > 0; check.dataset.taskId = task.id;
    check.setAttribute('aria-label', `${check.checked ? text("Restore") : text("Complete")} ${task.content}`);
    check.addEventListener('change', () => run(async () => render(await call('mutate', { owner, action: {
      kind: check.checked ? 'complete' : 'uncomplete', id: task.id,
    } }))));
    const edit = document.createElement('button'); edit.type = 'button'; edit.className = 'task-edit'; edit.disabled = busy > 0;
    const title = document.createElement('span'); title.className = 'task-title'; title.textContent = task.content;
    const meta = document.createElement('span'); meta.className = 'task-meta';
    const due = parseDue(task.dueJson), date = dueDay(task);
    const parts = [];
    if (date) parts.push(date + (due?.type === 'timed' ? ` · ${new Date(due.start).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : ''));
    if (due?.recurrence || due?.recurrenceSeriesId) parts.push(text("Repeating"));
    if (task.parentId) parts.push(text("Subtask"));
    if (task.projectId !== 'inbox') parts.push(state.records[`project:${task.projectId}`]?.name || text("Project"));
    if (task.priority < 4) parts.push(`P${task.priority}`);
    meta.textContent = parts.join(' · ');
    if (date && date < dateKey() && task.status !== 'completed') meta.classList.add('overdue');
    edit.append(title, meta); edit.addEventListener('click', () => openEditor(task));
    li.append(check, edit); fragment.append(li);
  }
  $('tasks').replaceChildren(fragment); $('empty').hidden = rows.length > 0; $('task-scroll').scrollTop = scroll;
  if (focusId) [...$('tasks').querySelectorAll('input')].find(el => el.dataset.taskId === focusId)?.focus({ preventScroll: true });
}
async function refresh() {
  if (!state?.user || document.hidden) return;
  if (syncing) { refreshAgain = true; return; }
  syncing = true; status();
  try { render(await call('sync')); } catch (e) { error(e.message); }
  finally {
    syncing = false; status();
    if (refreshAgain) { refreshAgain = false; queueMicrotask(refresh); }
  }
}
function showPanel() {
  const timerView = view === 'timer';
  $('task-panel').hidden = timerView; $('editor').hidden = true; $('timer-panel').hidden = !timerView;
}
function openEditor(task) {
  editing = task; dirty = new Set();
  const fields = scheduleFields(task.dueJson);
  $('edit-title').value = task.content; $('edit-description').value = task.description || '';
  $('edit-date').value = fields.date; $('edit-time').value = fields.time; $('edit-minutes').value = fields.minutes;
  $('edit-priority').value = task.priority ?? 4;
  const due = parseDue(task.dueJson);
  $('recurrence-note').hidden = !due?.recurrence && !due?.recurrenceSeriesId;
  $('task-panel').hidden = true; $('timer-panel').hidden = true; $('editor').hidden = false; $('edit-title').focus();
}
function closeEditor() { editing = null; showPanel(); }
for (const id of ['edit-date', 'edit-time', 'edit-minutes']) $(id).addEventListener('input', () => dirty.add(id));
$('cancel-edit').addEventListener('click', closeEditor);
$('clear-date').addEventListener('click', () => {
  $('edit-date').value = ''; $('edit-time').value = ''; dirty.add('edit-date'); dirty.add('edit-time');
});
$('delete-task').addEventListener('click', () => run(async () => {
  const subtasks = openSubtasks(state.records, editing.id);
  const prompt = deleteConfirmation(editing.content, subtasks);
  if (!confirm(text(prompt.message, prompt.values))) return;
  const result = await call('mutate', { owner, action: { kind: 'delete', id: editing.id } });
  closeEditor(); render(result);
}));
$('edit-form').addEventListener('submit', event => {
  event.preventDefault();
  run(async () => {
    const patch = {};
    if ($('edit-title').value.trim() !== editing.content) patch.content = $('edit-title').value;
    if ($('edit-description').value !== (editing.description || '')) patch.description = $('edit-description').value || null;
    if (Number($('edit-priority').value) !== editing.priority) patch.priority = Number($('edit-priority').value);
    if (dirty.size) {
      const dateOnly = dirty.size === 1 && dirty.has('edit-date');
      patch.dueJson = schedule($('edit-date').value, dateOnly ? undefined : $('edit-time').value,
        dateOnly ? undefined : Number($('edit-minutes').value), editing.dueJson);
    }
    const result = await call('mutate', { owner, action: { kind: 'edit', id: editing.id, patch } });
    closeEditor(); render(result);
  });
});
$('quick-add').addEventListener('submit', event => {
  event.preventDefault();
  run(async () => {
    const result = await call('mutate', { owner, action: { kind: 'create', content: $('new-title').value,
      description: null, dueJson: view === 'today' ? schedule(dateKey(), '', 30, null) : null } });
    $('new-title').value = ''; render(result);
  });
});
$('save-tab').addEventListener('click', () => run(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  render(await call('mutate', { owner, action: { kind: 'create', ...tabDraft(tab),
    dueJson: view === 'today' ? schedule(dateKey(), '', 30, null) : null } }));
}));
for (const tab of document.querySelectorAll('[data-view]')) {
  tab.addEventListener('click', () => {
    view = tab.dataset.view; closeEditor();
    for (const item of document.querySelectorAll('[data-view]')) { item.setAttribute('aria-selected', String(item === tab)); item.tabIndex = item === tab ? 0 : -1; }
    $('task-panel').setAttribute('aria-labelledby', tab.id); $('task-scroll').scrollTop = 0;
    if (view === 'timer') { showPanel(); startTicking(); } else { stopTicking(); render(state); }
  });
  tab.addEventListener('keydown', event => {
    const tabs = [...document.querySelectorAll('[data-view]')]; let index = tabs.indexOf(tab);
    if (event.key === 'ArrowRight') index = (index + 1) % tabs.length;
    else if (event.key === 'ArrowLeft') index = (index + tabs.length - 1) % tabs.length;
    else return;
    event.preventDefault(); tabs[index].click(); tabs[index].focus();
  });
}
$('refresh').addEventListener('click', refresh);
function clockText(timer) {
  const total = Math.ceil(remainingMs(timer) / 1000);
  return `${String(Math.floor(total / 60)).padStart(2, '0')}:${String(total % 60).padStart(2, '0')}`;
}
function paintTimer() {
  $('timer-display').textContent = clockText(timer);
  $('timer-phase').textContent = timer.phase === 'break' ? text("Break") : text("Focus");
  $('timer-toggle').firstElementChild.textContent = text(timer.running ? "Pause" : "Start");
  const total = phaseDuration(timer.phase, timer.minutes);
  $('timer-progress').value = total ? remainingMs(timer) / total : 0;
  for (const button of document.querySelectorAll('[data-minutes]')) {
    button.setAttribute('aria-pressed', String(Number(button.dataset.minutes) === timer.minutes));
  }
}
function saveTimer() {
  chrome.storage.session.set({ timer: { ...timer, savedAt: Date.now() } }).catch(() => {});
}
function beep() {
  try {
    const context = new AudioContext(), oscillator = context.createOscillator(), gain = context.createGain();
    oscillator.frequency.value = 880; gain.gain.value = 0.08;
    oscillator.connect(gain).connect(context.destination);
    oscillator.start(); oscillator.stop(context.currentTime + 0.35);
  } catch { /* Autoplay policies may refuse audio; the live region still announces the phase. */ }
}
function actTimer(action) {
  const { timer: next, effect } = reduce(timer, action);
  timer = next;
  if (effect) { $('timer-display').textContent = text(effect === 'focusEnded' ? "Break" : "Focus"); beep(); }
  paintTimer(); saveTimer();
}
function startTicking() { if (!timerTick) timerTick = setInterval(() => actTimer({ type: 'tick' }), 250); }
function stopTicking() { clearInterval(timerTick); timerTick = null; }
$('timer-toggle').addEventListener('click', () => actTimer({ type: timer.running ? 'pause' : 'start' }));
$('timer-reset').addEventListener('click', () => actTimer({ type: 'reset' }));
for (const button of document.querySelectorAll('[data-minutes]')) {
  button.addEventListener('click', () => actTimer({ type: 'setMinutes', minutes: Number(button.dataset.minutes) }));
}
$('login').addEventListener('submit', event => {
  event.preventDefault();
  const credentials = { email: $('email').value, password: $('password').value }; $('password').value = '';
  run(async () => render(await call('password', credentials)));
});
for (const provider of ['google', 'apple']) $(provider).addEventListener('click', () => run(async () => render(await call('oauth', { provider }))));
async function logout() {
  const discard = state.pending > 0;
  if (discard && !confirm(text("There are unsynced changes. Signing out will discard them on this device. Continue?"))) return;
  realtime.stop(); clearInterval(poll);
  render(await call('logout', { discard }));
}
$('logout').addEventListener('click', () => run(logout));
$('clear-account').addEventListener('click', () => run(logout));
chrome.runtime.onMessage.addListener((message, sender) => {
  if (sender.id === chrome.runtime.id && message?.event === 'state' && message.snapshot) render(message.snapshot);
});
window.addEventListener('online', refresh);
document.addEventListener('visibilitychange', () => {
  if (document.hidden) realtime.stop(); else if (state?.user) { realtime.start(); refresh(); }
});
window.addEventListener('pagehide', () => { realtime.stop(); clearInterval(poll); clearTimeout(hintTimer); stopTicking(); });
async function restoreTimer() {
  try {
    const saved = (await chrome.storage.session.get('timer')).timer;
    // Mirror the account-status cache guard: a stale or malformed payload is
    // discarded rather than trusted.
    if (saved && PRESETS.includes(saved.minutes) && ['focus', 'break'].includes(saved.phase) &&
        Number.isFinite(saved.remaining) && saved.remaining >= 0 && Date.now() - saved.savedAt < 86400000) {
      timer = { ...initial(saved.minutes), ...saved, remaining: remainingMs(saved), endsAt: saved.running ? saved.endsAt : null };
      if (timer.running && !Number.isFinite(timer.endsAt)) timer = { ...timer, running: false };
    }
  } catch { /* Session storage may be unavailable; the default timer is still usable. */ }
  paintTimer();
}
try { await restoreTimer(); render(await call('snapshot')); refresh(); } catch (e) { $('startup').hidden = true; error(e.message); }
