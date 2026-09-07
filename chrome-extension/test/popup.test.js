import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';
import * as core from '../src/core.js';

test('Add current tab saves immediately without consuming a typed task draft', async () => {
  const elements = new Map(), messages = [];
  const element = () => ({ value: '', dataset: {}, listeners: {}, classList: { add() {} },
    addEventListener(type, listener) { this.listeners[type] = listener; },
    setAttribute() {}, append() {}, replaceChildren() {}, querySelectorAll: () => [] });
  const get = id => { if (!elements.has(id)) elements.set(id, element()); return elements.get(id); };
  const views = ['today', 'inbox'].map(view => Object.assign(element(), { id: `tab-${view}`, dataset: { view } }));
  const snapshot = { user: { id: 'user-a', email: 'a@example.test' }, records: {}, pending: 0, error: '' };
  let currentTab = { title: 'A useful page', url: 'https://example.test/article' };
  // Run the actual popup handlers; replace only browser APIs and module imports.
  const source = (await readFile(new URL('../src/popup.js', import.meta.url), 'utf8')).replace(/^import .*;\n/gm, '');
  await vm.runInNewContext(`(async () => {${source}\n})()`, {
    ...core, config: { webUrl: 'https://app.example.test' },
    Realtime: class { start() {} stop() {} },
    document: { hidden: true, activeElement: element(), getElementById: get, createElement: element,
      createDocumentFragment: element, addEventListener() {},
      querySelectorAll: selector => selector === '[data-view]' ? views : [...elements.values()] },
    window: { addEventListener() {} }, setInterval() {}, clearInterval() {}, clearTimeout() {},
    chrome: { tabs: { query: async () => [currentTab] }, runtime: { onMessage: { addListener() {} },
      sendMessage: async message => { messages.push(structuredClone(message)); return { ok: true, value: snapshot }; } } },
  });
  get('new-title').value = 'My unfinished task';
  await get('save-tab').listeners.click();
  const saved = messages.filter(message => message.type === 'mutate');
  assert.equal(saved.length, 1);
  assert.deepEqual(saved[0].payload, { owner: 'user-a', action: { kind: 'create',
    content: 'A useful page', description: 'https://example.test/article', dueJson: core.schedule(core.dateKey(), '', 30, null) } });
  assert.equal(get('new-title').value, 'My unfinished task');
  views[1].listeners.click();
  await get('save-tab').listeners.click();
  assert.equal(messages.filter(message => message.type === 'mutate')[1].payload.action.dueJson, null);
  currentTab = { title: 'Settings', url: 'chrome://settings' };
  await get('save-tab').listeners.click();
  assert.equal(messages.filter(message => message.type === 'mutate').length, 2);
  assert.match(get('error').textContent, /HTTP/);
});
