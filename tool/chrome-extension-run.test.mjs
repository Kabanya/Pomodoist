import test from 'node:test';
import assert from 'node:assert/strict';
import { auditProbe, browserCandidates, devToolsSocket, extensionIdFromPreferences, findBrowser, noBrowserMessage } from './chrome-extension-run.mjs';

test('a testing build is preferred and a stable Chrome is never offered as a candidate', async () => {
  const candidates = await browserCandidates({ CHROME_BIN: '/custom/chrome' }, '/home/nobody');
  assert.equal(candidates[0], '/custom/chrome');
  assert.ok(candidates.some(candidate => /Chrome for Testing|Chromium/.test(candidate)));
  // Pointing at the stable app would silently load nothing, so it is excluded.
  assert.ok(!candidates.some(candidate => /^\/Applications\/Google Chrome\.app/.test(candidate)));
});

test('an unreadable Playwright cache is skipped instead of failing the lookup', async () => {
  const candidates = await browserCandidates({}, '/home/nobody');
  assert.ok(Array.isArray(candidates) && candidates.length > 0);
  assert.ok(!candidates.includes(''));
});

test('only an executable candidate is accepted, and a missing browser is explicit', async () => {
  assert.equal(await findBrowser(['/definitely/not/here', '/bin/sh']), '/bin/sh');
  assert.equal(await findBrowser(['/definitely/not/here']), null);
  assert.match(noBrowserMessage, /Chrome for Testing|Chromium/);
  assert.match(noBrowserMessage, /--load-extension/);
});

test('the DevTools endpoint is read from the split stderr stream', () => {
  const url = 'ws://127.0.0.1:51234/devtools/browser/abc-123';
  assert.equal(devToolsSocket(`noise\nDevTools listening on ${url}\nmore\n`), url);
  assert.equal(devToolsSocket('noise'), null);
  assert.equal(devToolsSocket(''), null);
});

test('the extension id is matched by resolved path, not by a guessed key', () => {
  const settings = { 'not-ours': { path: '/tmp/other' }, abcdefghijklmnopabcdefghijklmnop: { path: '/tmp/build/chrome/debug' } };
  const text = JSON.stringify({ extensions: { settings } });
  assert.equal(extensionIdFromPreferences(text, '/tmp/build/chrome/debug'), 'abcdefghijklmnopabcdefghijklmnop');
  assert.equal(extensionIdFromPreferences(text, '/tmp/build/chrome/debug/'), 'abcdefghijklmnopabcdefghijklmnop');
  assert.equal(extensionIdFromPreferences(text, '/tmp/elsewhere'), null);
  assert.equal(extensionIdFromPreferences('not json', '/tmp/build/chrome/debug'), null);
  assert.equal(extensionIdFromPreferences('{}', '/tmp/build/chrome/debug'), null);
});

const rendered = { tabs: ['today', 'upcoming', 'inbox', 'completed', 'timer'], title: 'Pomodoist',
  timerPanel: true, deleteButton: 'Delete', timerDisplay: '25:00',
  presets: ['15 minutes', '5 minutes', '25 minutes', '50 minutes'], signedOut: true };

test('a correctly rendered popup reports no problems', () => {
  assert.deepEqual(auditProbe(rendered), []);
});

test('a missing tab, timer panel, delete button, preset or clock is reported', () => {
  assert.deepEqual(auditProbe({ ...rendered, tabs: ['today'] }).length, 4);
  assert.match(auditProbe({ ...rendered, timerPanel: false })[0], /timer panel/);
  assert.match(auditProbe({ ...rendered, deleteButton: null })[0], /delete button/);
  assert.match(auditProbe({ ...rendered, timerDisplay: 'NaN:NaN' })[0], /timer shows/);
  assert.match(auditProbe({ ...rendered, timerDisplay: null })[0], /timer shows/);
  assert.deepEqual(auditProbe({ ...rendered, presets: [] })[0].startsWith('expected 4 presets'), true);
});

test('an unrendered popup is reported rather than treated as healthy', () => {
  const problems = auditProbe({});
  assert.ok(problems.length >= 5, 'an empty probe is never healthy');
  assert.equal(problems.some(problem => problem.includes('NaN')), false);
});
