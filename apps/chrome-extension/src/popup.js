import { text, localize } from './i18n.js';
import { config } from './config.js';
import { dateKey, deleteConfirmation, dueDay, openSubtasks, parseDue, schedule, scheduleFields, tabDraft, tasksFor } from './core.js';
import { PRESETS, preset, timerView } from './timer.js';
import { CATEGORIES, domain, bridgeOrigin } from './protection.js';
import { Realtime } from './realtime.js';
localize(document);
const $ = id => document.getElementById(id);
let state, view = 'today', editing = null, dirty = new Set(), busy = 0, live = false, syncing = false;
let owner = null, poll, hintTimer, refreshAgain = false;
let minutes=25,timerTick=null,selectedProfile=null;
// Every timer read goes through one clock accessor, so the countdown, the
// deadline and the cache timestamp can never disagree about "now".
const now = () => Date.now();
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
  finally { busy--; lock(); paintTimer(); }
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
  $('startup').hidden = true; $('auth').hidden = !!owner; $('app').hidden = !owner && !state.protection?.paired;
  paintTimer(); paintProtection();
  if(!owner && state.protection?.paired){view='timer';showPanel();startTicking();}
  for(const tab of document.querySelectorAll('[data-view]'))tab.hidden=!owner&&tab.dataset.view!=='timer';
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
    if (view === 'timer') { showPanel(); startTicking(); run(async()=>render(await call('focusRead'))); } else { stopTicking(); render(state); }
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
function currentTimer(){return timerView(state?.focus,state?.focusReadAt??now(),now(),minutes);}
function paintTimer(){
  const timer=currentTimer(),left=timer.remaining;
  $('focus-task').textContent=state?.focus?.session?.taskTitle||state?.records?.[`task:${state?.focus?.session?.run?.taskId}`]?.content||text('Return to your task.');
  $('timer-display').textContent=`${String(Math.floor(left/60)).padStart(2,'0')}:${String(left%60).padStart(2,'0')}`;
  const pendingExit=timer.exitRequestedAt||state?.protection?.exitRequestedAt;
  $('timer-phase').textContent=pendingExit?text('Strict exit countdown is active.'):timer.phase==='work'?text('Focus'):text('Break');
  $('timer-toggle').firstElementChild.textContent=text(timer.status==='running'?'Pause':timer.status==='paused'?'Resume':'Start');
  $('timer-progress').value=timer.total?left/timer.total:0;
  const ongoing=!!state?.focus?.session && ['active','paused','running'].includes(state.focus.session.run?.status);
  for(const button of document.querySelectorAll('[data-minutes]')){button.setAttribute('aria-pressed',String(Number(button.dataset.minutes)===minutes));button.disabled=busy>0||ongoing;}
  $('strict-focus').disabled=busy>0||ongoing;$('exit-policy').disabled=busy>0||ongoing;
  $('focus-profile').disabled=busy>0||ongoing;
  $('auto-classify').disabled=busy>0||!state?.protection?.isPro;
  $('cancel-stop').hidden=!pendingExit;
}
function startTicking(){if(!timerTick)timerTick=setInterval(paintTimer,250);}
function stopTicking(){clearInterval(timerTick);timerTick=null;}
async function focusCommand(action,payload){render(await call('focus',{action,payload}));}
$('timer-toggle').addEventListener('click',()=>run(async()=>{
  const t=currentTimer();
  if(t.status==='running')await focusCommand('pause');
  else if(t.status==='paused')await focusCommand('resume');
  else if(t.status==='ready')await focusCommand('startReady');
  else await focusCommand('start',{preset:preset(minutes,$('strict-focus').checked),profileId:$('focus-profile').value||null,strictExitSeconds:Number($('exit-policy').value)});
}));
$('timer-reset').addEventListener('click',()=>run(async()=>{
  if(state?.focus?.session?.preset?.strictMode && state.focus.session.strictExitSeconds===0 && !confirm(text('End strict Focus now?')))return;
  await focusCommand('requestStop',{confirmed:true});
}));
$('cancel-stop').addEventListener('click',()=>run(()=>focusCommand('cancelStop')));
for(const button of document.querySelectorAll('[data-minutes]'))button.addEventListener('click',()=>{minutes=Number(button.dataset.minutes);paintTimer();});
function options(select,values,selected){
  const children=values.map(([value,label])=>{const o=document.createElement('option');o.value=value;o.textContent=text(label);return o;});
  select.replaceChildren(...children);select.value=selected??'';
}
for(const id of ['domain-category','profile-categories']) options($(id),CATEGORIES.filter(c=>id!=='profile-categories'||c!=='unclassified').map(c=>[c,c]));
$('bridge-port').value=String({production:51987,staging:51988,development:51989}[config.flavor??'production']);
function paintProtection(){
  const p=state?.protection??{};
  $('enable-protection').checked=!!p.enabled;
  $('emergency-release').hidden=!p.authorityUnavailable;
  $('auto-classify').checked=!!p.autoClassify;$('auto-classify').disabled=busy>0||!p.isPro;
  $('classification-error').textContent=text(p.classificationError||'');
  $('focus-source').value=p.source??'cloud';
  $('protection-status').textContent=text(p.hostPermission?(p.active?'Website protection active':'Website access allowed · protection idle'):'Website permission required')+' · '+text(p.incognito?'Incognito allowed':'Incognito not enabled')+(p.error?' · '+text(p.error):'');
  const profiles=(state?.focus?.profiles??[]).filter(p=>!p.isDeleted);
  const selected=$('focus-profile').value || state?.focus?.session?.profileId || '';
  options($('focus-profile'),[['','No blocking profile'],...profiles.map(p=>[p.id,p.name])],selected);
  const editor=$('edit-profile').value||selectedProfile||profiles[0]?.id||'';
  options($('edit-profile'),[['','New profile'],...profiles.map(p=>[p.id,p.name])],editor);
  const discovered=p.discovered??[];
  const fragment=document.createDocumentFragment();
  for(const host of discovered){const o=document.createElement('option');o.value=host;fragment.append(o);}
  $('discovered-domains').replaceChildren(fragment);
}
function loadProfile(){
  const p=state?.focus?.profiles?.find(p=>p.id===$('edit-profile').value);
  selectedProfile=p?.id??null;
  $('profile-name').value=p?.name??'';
  for(const o of $('profile-categories').options??[])o.selected=p?.blockedCategories?.includes(o.value)??false;
  $('block-pause').checked=p?.blockOnPause!==false;
  $('block-short').checked=p?.blockOnShortBreak===true;
  $('block-long').checked=p?.blockOnLongBreak===true;
}
$('edit-profile').addEventListener('change',loadProfile);
$('profile-form').addEventListener('submit',event=>{event.preventDefault();run(async()=>{
  const previous=state?.focus?.profiles?.find(p=>p.id===$('edit-profile').value);
  const name=$('profile-name').value.trim();if(!name||name.length>100)throw new Error('Enter a profile name.');
  const profile={...previous,id:previous?.id??crypto.randomUUID(),name,blockedCategories:[...$('profile-categories').selectedOptions].map(o=>o.value),overrides:previous?.overrides??[],
    blockOnPause:$('block-pause').checked,blockOnShortBreak:$('block-short').checked,blockOnLongBreak:$('block-long').checked,updatedAt:new Date().toISOString()};
  await focusCommand('profileUpsert',{profile});selectedProfile=profile.id;$('edit-profile').value=profile.id;loadProfile();
});});
$('domain-form').addEventListener('submit',event=>{event.preventDefault();run(async()=>{
  const id=domain($('domain-name').value);if(!id)throw new Error('Enter a valid domain.');
  const assignment={id,kind:'domain',name:id.slice(0,100),category:$('domain-category').value,source:'manual',updatedAt:new Date().toISOString()};
  const p=state?.focus?.profiles?.find(p=>p.id===$('edit-profile').value),action=$('domain-override').value;
  if(!p && action!=='category')throw new Error('Choose a profile for an explicit domain rule.');
  await focusCommand('assignmentUpsert',{assignment});
  if(p){const overrides=p.overrides.filter(r=>r.kind!=='domain'||r.id!==id);if(action!=='category')overrides.push({kind:'domain',id,action});await focusCommand('profileUpsert',{profile:{...p,overrides,updatedAt:new Date().toISOString()}});}
});});
$('auto-classify').addEventListener('change',()=>run(async()=>render(await call('protection',{autoClassify:$('auto-classify').checked}))));
$('enable-protection').addEventListener('change',()=>run(async()=>{
  const enabled=$('enable-protection').checked;
  if(enabled && !await chrome.permissions.request({origins:['http://*/*','https://*/*']}))throw new Error('Allow website access to enable protection.');
  if(!enabled && !await confirmDetach())return;
  render(await call('protection',{enabled,confirmed:true}));
}));
async function confirmDetach(){render(await call('focusRead'));return !state?.focus?.session?.preset?.strictMode||state.focus.session.strictExitSeconds!==0||confirm(text('Release strict protection on this browser now?'));}
$('focus-source').addEventListener('change',()=>run(async()=>{if(await confirmDetach())render(await call('protection',{source:$('focus-source').value,confirmed:true}));}));
$('pair-form').addEventListener('submit',event=>{event.preventDefault();run(async()=>{
  const port=$('bridge-port').value,code=$('pair-code').value;
  const origin=bridgeOrigin(port);
  if(!await chrome.permissions.request({origins:[`${origin}/*`]}))throw new Error('Allow access to the desktop bridge.');
  if(!await confirmDetach())return;
  render(await call('pair',{port,code,confirmed:true}));$('pair-code').value='';
});});
$('emergency-release').addEventListener('click',()=>run(async()=>{
  if(confirm(text('Release protection on this browser only? Shared Focus will continue.')))render(await call('emergencyRelease',{confirm:true}));
}));
$('login').addEventListener('submit', event => {
  event.preventDefault();
  const credentials = { email: $('email').value, password: $('password').value }; $('password').value = '';
  run(async () => render(await call('password', credentials)));
});
for (const provider of ['google', 'apple']) $(provider).addEventListener('click', () => run(async () => render(await call('oauth', { provider }))));
async function logout() {
  if(!await confirmDetach())return;
  const discard = state.pending > 0;
  if (discard && !confirm(text("There are unsynced changes. Signing out will discard them on this device. Continue?"))) return;
  realtime.stop(); clearInterval(poll);
  render(await call('logout', { discard,confirmed:true }));
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
paintTimer();
try { render(await call('snapshot')); loadProfile(); refresh(); } catch (e) { $('startup').hidden = true; error(e.message); }
