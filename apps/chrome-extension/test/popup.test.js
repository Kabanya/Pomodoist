import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import * as core from '../src/core.js';
import * as timer from '../src/timer.js';
import { text } from '../src/i18n.js';

// The popup module is a browser entry point, so its imports are stripped and
// replaced with the real modules plus the smallest possible browser stubs. The
// handlers under test are the shipped ones.
const BASE_TIME = 1_800_000_000_000;
async function loadPopup({ snapshot = {}, confirm = () => true, currentTab, startAt = 0 } = {}) {
  const elements = new Map(), messages = [], ticks = [], created = [];
  const time = { now: BASE_TIME + startAt };
  const element = () => { const node = { value: '', dataset: {}, listeners: {}, hidden: false, classList: { add() {} },
    firstElementChild: { textContent: '' },
    addEventListener(type, listener) { this.listeners[type] = listener; },
    setAttribute() {}, append() {}, replaceChildren() {}, querySelectorAll: () => [], focus() {} };
    created.push(node); return node; };
  const get = id => { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); };
  const views = ['today', 'inbox', 'timer'].map(view => Object.assign(element(), { id: `tab-${view}`, dataset: { view } }));
  const presets = [15, 5, 25, 50].map(minutes => Object.assign(element(), { dataset: { minutes: String(minutes) } }));
  const source = (await readFile(new URL('../src/popup.js', import.meta.url), 'utf8')).replace(/^import .*;\n/gm, '');
  const context = {
    ...core, ...timer, text, localize() {}, config: { webUrl: 'https://app.example.test' },
    Realtime: class { start() {} stop() {} }, confirm, Date: FakeDate(time),
    document: { hidden: true, activeElement: element(), getElementById: get, createElement: element,
      createDocumentFragment: element, addEventListener() {},
      querySelectorAll: selector => selector === '[data-view]' ? views : selector === '[data-minutes]' ? presets : [...elements.values()] },
    window: { addEventListener() {} }, queueMicrotask: () => {}, clearTimeout() {}, clearInterval() {},
    setInterval: callback => { ticks.push(callback); return 'handle'; },
    AudioContext: class { constructor() { this.currentTime = 0; this.destination = {}; }
      createOscillator() { return { frequency: {}, connect: () => ({ connect() {} }), start() {}, stop() {} }; }
      createGain() { return { gain: {}, connect: () => ({ connect() {} }) }; } },
    chrome: { tabs: { query: async () => [currentTab] }, runtime: { onMessage: { addListener() {} },
        sendMessage: async message => { messages.push(structuredClone(message)); return { ok: true, value: snapshot }; } },
      storage: { session: { get: async () => ({}), set: async () => {} } } },
  };
  // The popup awaits its first snapshot at module scope, so evaluation resolves
  // only once render() has run and state is populated.
  await vm.runInNewContext(`(async () => {${source}\n})()`, context);
  return { elements, get, views, presets, messages, ticks, created,
    advance: ms => { time.now += ms; } };
}
// A Date whose zero-argument form reads the shared test clock, so the
// wall-clock countdown is exercised without waiting for real time to pass.
function FakeDate(time) {
  return class extends Date {
    constructor(...args) { super(...(args.length ? args : [time.now])); }
    static now() { return time.now; }
  };
}
// Opening a row is the only supported path into the editor, so the test uses
// the very button the list rendered rather than writing state directly. The
// Inbox view is where undated tasks live.
const openFirstTask = popup => {
  popup.views[1].listeners.click();
  const edit = popup.created.find(node => node.className === 'task-edit' && node.listeners.click);
  assert.ok(edit, 'the list rendered a task row');
  edit.listeners.click();
};
const snapshotFor = records => ({ user: { id: 'user-a', email: 'a@example.test' }, records, pending: 0, error: '', overview: null });
const task = (id, extra = {}) => ({ id, content: id, projectId: 'inbox', status: 'open', dueJson: null, priority: 4, ...extra });

test('Add current tab saves immediately without consuming a typed task draft', async () => {
  const popup = await loadPopup({ snapshot: snapshotFor({}), currentTab: { title: 'A useful page', url: 'https://example.test/article' } });
  popup.get('new-title').value = 'My unfinished task';
  await popup.get('save-tab').listeners.click();
  const saved = popup.messages.filter(message => message.type === 'mutate');
  assert.equal(saved.length, 1);
  assert.deepEqual(saved[0].payload, { owner: 'user-a', action: { kind: 'create',
    content: 'A useful page', description: 'https://example.test/article', dueJson: core.schedule(core.dateKey(), '', 30, null) } });
  assert.equal(popup.get('new-title').value, 'My unfinished task');
  await popup.views[1].listeners.click();
  await popup.get('save-tab').listeners.click();
  assert.equal(popup.messages.filter(message => message.type === 'mutate')[1].payload.action.dueJson, null);
});

test('a privileged tab is refused instead of being created as a task', async () => {
  const popup = await loadPopup({ snapshot: snapshotFor({}), currentTab: { title: 'Settings', url: 'chrome://settings' } });
  await popup.get('save-tab').listeners.click();
  assert.equal(popup.messages.filter(message => message.type === 'mutate').length, 0);
  assert.match(popup.get('error').textContent, /HTTP/);
});

test('deleting from the editor sends one delete action, and declining sends none', async () => {
  const records = { 'task:a': task('a'), 'task:child': task('child', { parentId: 'a' }) };
  const declined = await loadPopup({ snapshot: snapshotFor(records), confirm: () => false });
  await openFirstTask(declined);
  await declined.get('delete-task').listeners.click();
  assert.equal(declined.messages.filter(message => message.type === 'mutate').length, 0);

  const confirmed = await loadPopup({ snapshot: snapshotFor(records), confirm: () => true });
  await openFirstTask(confirmed);
  await confirmed.get('delete-task').listeners.click();
  const deletes = confirmed.messages.filter(message => message.type === 'mutate');
  assert.equal(deletes.length, 1);
  assert.deepEqual(deletes[0].payload.action, { kind: 'delete', id: 'a' });
});

test('the timer tab shows the timer instead of the task panel and starts no task work', async () => {
  const popup = await loadPopup({ snapshot: snapshotFor({}) });
  await popup.views[2].listeners.click();
  assert.equal(popup.get('task-panel').hidden, true);
  assert.equal(popup.get('timer-panel').hidden, false);
  assert.equal(popup.messages.filter(message => message.type === 'mutate').length, 0);
  assert.equal(popup.get('timer-display').textContent, '25:00');
  assert.equal(popup.get('timer-phase').textContent, 'Focus');

  await popup.views[0].listeners.click();
  assert.equal(popup.get('task-panel').hidden, false);
  assert.equal(popup.get('timer-panel').hidden, true);
});

test('timer controls drive the countdown through the same reducer the tests cover', async () => {
  const popup = await loadPopup({ snapshot: snapshotFor({}) });
  await popup.views[2].listeners.click();
  await popup.get('timer-toggle').listeners.click();
  assert.equal(popup.get('timer-toggle').firstElementChild.textContent, 'Pause');
  assert.equal(popup.get('timer-phase').textContent, 'Focus');
  assert.ok(popup.ticks.length >= 1, 'the timer installed a tick callback');

  popup.advance(5 * 60 * 1000);
  await popup.ticks.at(-1)();
  assert.equal(popup.get('timer-display').textContent, '20:00');

  await popup.get('timer-reset').listeners.click();
  assert.equal(popup.get('timer-toggle').firstElementChild.textContent, 'Start');
  assert.equal(popup.get('timer-display').textContent, '25:00');
});

test('a finished phase is announced in the live region, not only shown by colour', async () => {
  const popup = await loadPopup({ snapshot: snapshotFor({}) });
  await popup.views[2].listeners.click();
  await popup.presets[0].listeners.click();            // 15 minutes
  await popup.get('timer-toggle').listeners.click();
  popup.advance(15 * 60 * 1000);
  await popup.ticks.at(-1)();                          // the real interval callback
  assert.equal(popup.get('timer-phase').textContent, 'Focus session complete. Take a break.');
  assert.equal(popup.get('timer-display').textContent, '05:00');
  assert.equal(popup.get('timer-toggle').firstElementChild.textContent, 'Pause');

  popup.advance(5 * 60 * 1000);
  await popup.ticks.at(-1)();
  assert.equal(popup.get('timer-phase').textContent, 'Break over. Ready to focus?');
  assert.equal(popup.get('timer-toggle').firstElementChild.textContent, 'Start');
});
