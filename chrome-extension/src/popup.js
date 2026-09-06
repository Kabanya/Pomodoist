import { config } from './config.js';
import { dateKey, dueDay, parseDue, schedule, scheduleFields, tabDraft, tasksFor } from './core.js';
import { Realtime } from './realtime.js';
const $ = id => document.getElementById(id);
let state, view = 'today', editing = null, dirty = new Set(), draftDescription = '', busy = 0, live = false, syncing = false;
let owner = null, poll, hintTimer, refreshAgain = false;
const realtime = new Realtime(() => call('realtime'), () => {
  clearTimeout(hintTimer); hintTimer = setTimeout(refresh, 150);
}, connected => { live = connected; status(); });
$('open-app').href = config.webUrl;
async function call(type, payload = {}) {
  const result = await chrome.runtime.sendMessage({ type, payload });
  if (!result?.ok) throw new Error(result?.error || 'The extension did not respond. Reopen it and retry.');
  return result.value;
}
function error(message = '') { $('error').textContent = message; $('error').hidden = !message; }
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
  $('connection').textContent = pending ? `${pending} changes saved locally · waiting to sync` : syncing ? 'Syncing…' :
    state.error ? 'Offline or sync needs attention' : state.lastSyncedAt ? (live ? 'Live sync' : 'Synced · periodic refresh') : 'Loading account data…';
  const overview = state.overview, profile = overview?.profile;
  const app = overview?.apps?.find(item => (item.id ?? item.appId ?? item.app_id) === 'pomodoist');
  let plan = 'Plan unavailable';
  if (profile) {
    const active = app?.entitlements?.some(item => item.status === 'active' &&
      (!(item.validUntil ?? item.valid_until) || new Date(item.validUntil ?? item.valid_until).getTime() > Date.now()));
    plan = (profile.pomodoistIsPro ?? profile.pomodoist_is_pro) ? 'Pro' : active ? 'Account access active' : 'Free';
    if (Date.now() - state.overviewAt > 90000) plan += ' (cached)';
  }
  $('account').textContent = `${state.user.email} · ${plan}`;
  $('account').title = state.overviewAt ? `Account status checked ${new Date(state.overviewAt).toLocaleString()}` : 'Account status has not been loaded.';
}
function render(next) {
  const previousOwner = owner;
  state = next; owner = state.user?.id ?? null;
  $('startup').hidden = true; $('auth').hidden = !!owner; $('app').hidden = !owner;
  $('clear-account').hidden = !!owner || !state.pending;
  if (previousOwner !== owner) {
    editing = null; $('editor').hidden = true; $('task-panel').hidden = false;
    $('new-title').value = ''; draftDescription = ''; $('tab-preview').hidden = true;
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
    check.setAttribute('aria-label', `${check.checked ? 'Restore' : 'Complete'} ${task.content}`);
    check.addEventListener('change', () => run(async () => render(await call('mutate', { owner, action: {
      kind: check.checked ? 'complete' : 'uncomplete', id: task.id,
    } }))));
    const edit = document.createElement('button'); edit.type = 'button'; edit.className = 'task-edit'; edit.disabled = busy > 0;
    const title = document.createElement('span'); title.className = 'task-title'; title.textContent = task.content;
    const meta = document.createElement('span'); meta.className = 'task-meta';
    const due = parseDue(task.dueJson), date = dueDay(task);
    const parts = [];
    if (date) parts.push(date + (due?.type === 'timed' ? ` · ${new Date(due.start).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}` : ''));
    if (due?.recurrence || due?.recurrenceSeriesId) parts.push('Repeating');
    if (task.parentId) parts.push('Subtask');
    if (task.projectId !== 'inbox') parts.push(state.records[`project:${task.projectId}`]?.name || 'Project');
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
function openEditor(task) {
  editing = task; dirty = new Set();
  const fields = scheduleFields(task.dueJson);
  $('edit-title').value = task.content; $('edit-description').value = task.description || '';
  $('edit-date').value = fields.date; $('edit-time').value = fields.time; $('edit-minutes').value = fields.minutes;
  $('edit-priority').value = task.priority ?? 4;
  const due = parseDue(task.dueJson);
  $('recurrence-note').hidden = !due?.recurrence && !due?.recurrenceSeriesId;
  $('task-panel').hidden = true; $('editor').hidden = false; $('edit-title').focus();
}
function closeEditor() { editing = null; $('editor').hidden = true; $('task-panel').hidden = false; }
for (const id of ['edit-date', 'edit-time', 'edit-minutes']) $(id).addEventListener('input', () => dirty.add(id));
$('cancel-edit').addEventListener('click', closeEditor);
$('clear-date').addEventListener('click', () => {
  $('edit-date').value = ''; $('edit-time').value = ''; dirty.add('edit-date'); dirty.add('edit-time');
});
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
      description: draftDescription || null, dueJson: view === 'today' ? schedule(dateKey(), '', 30, null) : null } });
    $('new-title').value = ''; draftDescription = ''; $('tab-preview').hidden = true; render(result);
  });
});
$('save-tab').addEventListener('click', () => run(async () => {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  const draft = tabDraft(tab); $('new-title').value = draft.content; draftDescription = draft.description;
  $('tab-preview').textContent = `${draft.description} — review, then press Add to save.`; $('tab-preview').hidden = false;
}));
for (const tab of document.querySelectorAll('[data-view]')) {
  tab.addEventListener('click', () => {
    view = tab.dataset.view; closeEditor();
    for (const item of document.querySelectorAll('[data-view]')) { item.setAttribute('aria-selected', String(item === tab)); item.tabIndex = item === tab ? 0 : -1; }
    $('task-panel').setAttribute('aria-labelledby', tab.id); $('task-scroll').scrollTop = 0; render(state);
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
$('login').addEventListener('submit', event => {
  event.preventDefault();
  const credentials = { email: $('email').value, password: $('password').value }; $('password').value = '';
  run(async () => render(await call('password', credentials)));
});
for (const provider of ['google', 'apple']) $(provider).addEventListener('click', () => run(async () => render(await call('oauth', { provider }))));
async function logout() {
  const discard = state.pending > 0;
  if (discard && !confirm('There are unsynced changes. Signing out will discard them on this device. Continue?')) return;
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
window.addEventListener('pagehide', () => { realtime.stop(); clearInterval(poll); clearTimeout(hintTimer); });
try { render(await call('snapshot')); refresh(); } catch (e) { $('startup').hidden = true; error(e.message); }
