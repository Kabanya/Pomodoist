#!/usr/bin/env node
// Runs the built Chrome extension in a real browser: loads it, opens the popup
// and reports what the popup rendered. Chrome 137+ ignores --load-extension in
// stable builds, so this looks for Chrome for Testing or a Playwright Chromium
// and refuses to pretend a stable Chrome worked.
import { constants } from 'node:fs';
import { access, mkdir, readFile } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { homedir, tmpdir } from 'node:os';
import { parseArgs } from 'node:util';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

export const root = fileURLToPath(new URL('../', import.meta.url));
export const DEFAULT_PROFILE = path.join(tmpdir(), 'pomodoist-chrome-extension');

// --load-extension is honoured by testing builds only. A stable Chrome accepts
// the flag and silently loads nothing, which is the failure this list prevents.
export async function browserCandidates(env = process.env, home = homedir()) {
  const candidates = [env.CHROME_BIN];
  if (process.platform === 'darwin') {
    candidates.push(
      '/Applications/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
      '/Applications/Chromium.app/Contents/MacOS/Chromium',
    );
  } else if (process.platform === 'win32') {
    candidates.push(
      path.join(env.LOCALAPPDATA ?? '', 'Google/Chrome for Testing/Application/chrome.exe'),
    );
  } else {
    candidates.push('/usr/bin/chromium', '/usr/bin/chromium-browser');
  }
  try {
    candidates.push(...(await playwrightChromium(path.join(home, 'Library/Caches/ms-playwright'))),
      ...(await playwrightChromium(path.join(home, '.cache/ms-playwright'))));
  } catch {
    // A missing Playwright cache is normal; the other candidates still apply.
  }
  return candidates.filter(Boolean);
}

async function playwrightChromium(cache) {
  const { readdir } = await import('node:fs/promises');
  let entries;
  try {
    entries = await readdir(cache);
  } catch {
    return [];
  }
  const relative = process.platform === 'darwin'
    ? 'chrome-mac/Chromium.app/Contents/MacOS/Chromium'
    : process.platform === 'win32' ? 'chrome-win/chrome.exe' : 'chrome-linux/chrome';
  return entries.filter(name => name.startsWith('chromium-')).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }))
    .map(name => path.join(cache, name, relative));
}

export async function findBrowser(candidates) {
  for (const candidate of candidates) {
    try {
      await access(candidate, constants.X_OK);
      return candidate;
    } catch {
      // Keep looking; only an executable candidate is usable.
    }
  }
  return null;
}

export const noBrowserMessage = 'No Chrome for Testing or Chromium found. Stable Chrome ignores --load-extension (Chrome 137+), ' +
  'so the extension cannot be loaded there. Install Chrome for Testing or run npx playwright install chromium, or set CHROME_BIN.';

// Chrome writes the browser websocket endpoint to stderr once, never via a fixed
// port, because this passes --remote-debugging-port=0.
export function devToolsSocket(output) {
  const match = output.match(/DevTools listening on (ws:\/\/[^\s]+)/);
  return match ? match[1] : null;
}

export function extensionIdFromPreferences(text, extensionPath) {
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    return null;
  }
  const settings = parsed?.extensions?.settings ?? {};
  for (const [id, value] of Object.entries(settings)) {
    if (value?.path && path.resolve(value.path) === path.resolve(extensionPath)) return id;
  }
  return null;
}

// Read-only: reports what the popup actually rendered, so a broken build fails
// loudly instead of opening a blank panel.
export const probeExpression = `JSON.stringify({
  tabs: [...document.querySelectorAll('[data-view]')].map(node => node.dataset.view),
  title: document.title,
  timerPanel: !!document.getElementById('timer-panel'),
  deleteButton: document.getElementById('delete-task')?.textContent.trim() ?? null,
  timerDisplay: document.getElementById('timer-display')?.textContent ?? null,
  timerPhase: document.getElementById('timer-phase')?.textContent ?? null,
  presets: [...document.querySelectorAll('[data-minutes]')].map(node => node.textContent.trim()),
  rows: document.querySelectorAll('#tasks li.task').length,
  tasksShown: !document.getElementById('task-panel').hidden,
  signedOut: !document.getElementById('auth').hidden,
  appShown: !document.getElementById('app').hidden,
})`;

export function auditProbe(probe) {
  const problems = [];
  const required = ['today', 'upcoming', 'inbox', 'completed', 'timer'];
  for (const tab of required) if (!probe.tabs?.includes(tab)) problems.push(`tab "${tab}" did not render`);
  if (!probe.timerPanel) problems.push('the timer panel is missing');
  if (probe.deleteButton !== 'Delete') problems.push(`the delete button reads ${JSON.stringify(probe.deleteButton)}`);
  if (!/^\d{2}:\d{2}$/.test(probe.timerDisplay ?? '')) problems.push(`the timer shows ${JSON.stringify(probe.timerDisplay)}`);
  if (probe.presets?.length !== 4) problems.push(`expected 4 presets, saw ${probe.presets?.length ?? 0}`);
  return problems;
}

// Signing in needs a real account, but the popup renders purely from the
// snapshot it requests over chrome.runtime. Stubbing that one boundary lets the
// authenticated UI be inspected and screenshotted without credentials. The stub
// is installed before the popup module runs, so no account request escapes.
export function previewSnapshot(nowTime = Date.now()) {
  const now = nowTime;
  const task = (id, content, due, extra = {}) => ({ id, userId: 'local-user', content, description: null,
    projectId: 'inbox', sectionId: null, parentId: null, priority: 4, dueJson: due, deadlineJson: null,
    durationSeconds: null, status: 'open', estimatedFocusIntervals: null, completedFocusIntervals: 0,
    totalFocusSeconds: 0, orderKey: String(now * 1000 + id.length).padStart(20, '0'), dayOrder: null,
    isCollapsed: false, isDeleted: false, createdAt: now, updatedAt: now, completedAt: null, ...extra });
  // Dates are relative to when the stub is installed, not to module load, so a
  // long-lived browser session does not silently drift past "today".
  const day = offset => {
    const d = new Date(now);
    d.setDate(d.getDate() + offset);
    return JSON.stringify({ type: 'allDay', date: [d.getFullYear(), String(d.getMonth() + 1).padStart(2, '0'), String(d.getDate()).padStart(2, '0')].join('-') });
  };
  return { user: { id: 'preview-user', email: 'preview@example.test' },
    records: {
      'task:1': task('1', 'Review the pull request', day(-1)),
      'task:2': task('2', 'Write the migration notes', day(0), { priority: 2 }),
      'task:3': task('3', 'Book the venue for the offsite', day(0), { priority: 3 }),
      'task:4': task('4', 'Draft the quarterly summary', day(3)),
      'task:5': task('5', 'Send the invoice', day(0), { status: 'completed', completedAt: now }),
      'project:inbox': { id: 'inbox', name: 'Inbox', isDeleted: false, isArchived: false },
    }, pending: 0, overview: null, overviewAt: 0, lastSyncedAt: now, error: '' };
}

export function previewStub(snapshot = previewSnapshot()) {
  return `(() => {
    const snapshot = ${JSON.stringify(snapshot)};
    chrome.runtime.sendMessage = async (message) => {
      // Every command the popup issues must stay local, or the real background
      // answers with a signed-out snapshot and overwrites the preview.
      switch (message?.type) {
        case 'snapshot': return { ok: true, value: snapshot };
        case 'sync': return { ok: true, value: snapshot };
        case 'mutate': return { ok: true, value: snapshot };
        default: return { ok: false, error: 'preview' };
      }
    };
    // The background also pushes state events; those carry the real account.
    chrome.runtime.onMessage = { addListener() {}, removeListener() {}, hasListener: () => false };
    // Realtime would open a socket with no session. It is not needed to render.
    Object.defineProperty(globalThis, 'WebSocket', { value: class { constructor() { this.readyState = 3; } send() {} close() {} addEventListener() {} } });
  })();`;
}

class Cdp {
  constructor(socket) {
    this.socket = socket; this.nextId = 1; this.pending = new Map();
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      const pending = message.id ? this.pending.get(message.id) : null;
      if (!pending) return;
      this.pending.delete(message.id);
      message.error ? pending.reject(new Error(message.error.message)) : pending.resolve(message.result ?? {});
    });
  }
  send(method, params = {}, sessionId) {
    const id = this.nextId++;
    this.socket.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }
}

const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function launch(browser, profile, extensionPath) {
  const child = spawn(browser, ['--remote-debugging-port=0', `--user-data-dir=${profile}`, `--load-extension=${extensionPath}`,
    '--no-first-run', '--no-default-browser-check', '--disable-sync', '--disable-background-networking', 'about:blank'],
    { stdio: ['ignore', 'ignore', 'pipe'] });
  let output = '', spawnError;
  child.on('error', error => { spawnError = error; });
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', chunk => { output += chunk; });
  for (let attempt = 0; attempt < 100; attempt++) {
    const socket = devToolsSocket(output);
    if (socket) return { child, socket };
    if (spawnError) throw spawnError;
    if (child.exitCode !== null) throw new Error(`The browser exited before DevTools was ready: ${output.slice(-400)}`);
    await delay(100);
  }
  throw new Error(`Timed out waiting for DevTools: ${output.slice(-400)}`);
}

async function main() {
  const { values } = parseArgs({ options: {
    extension: { type: 'string' }, profile: { type: 'string' }, 'keep-profile': { type: 'boolean' },
    await: { type: 'string' }, screenshot: { type: 'string' },
    preview: { type: 'boolean' }, view: { type: 'string' }, 'no-open': { type: 'boolean' },
  } });
  const extensionPath = path.resolve(values.extension ?? path.join(root, 'build/chrome/debug'));
  const profile = path.resolve(values.profile ?? DEFAULT_PROFILE);
  try {
    await access(path.join(extensionPath, 'manifest.json'), constants.R_OK);
  } catch {
    throw new Error(`No built extension at ${extensionPath}. Run make chrome-debug first.`);
  }
  const browser = await findBrowser(await browserCandidates());
  if (!browser) throw new Error(noBrowserMessage);
  console.log(`Browser:   ${browser}`);
  console.log(`Extension: ${extensionPath}`);
  console.log(`Profile:   ${profile}`);
  await mkdir(profile, { recursive: true });

  const { child, socket: browserSocket } = await launch(browser, profile, extensionPath);
  let cleaned = false;
  const shutdown = async () => {
    if (cleaned) return;
    cleaned = true;
    if (child.exitCode === null) {
      const exited = new Promise(resolve => child.once('exit', resolve));
      child.kill('SIGTERM');
      await Promise.race([exited, delay(1000)]);
      if (child.exitCode === null) { child.kill('SIGKILL'); await Promise.race([exited, delay(1000)]); }
    }
  };
  let socket;
  try {
    socket = new WebSocket(browserSocket);
    await new Promise((resolve, reject) => {
      socket.addEventListener('open', resolve, { once: true });
      socket.addEventListener('error', reject, { once: true });
    });
    const cdp = new Cdp(socket);
    // The extension id is derived from the profile, so a re-run keeps it stable.
    let extensionId = null;
    for (let attempt = 0; attempt < 60 && !extensionId; attempt++) {
      const preferences = path.join(profile, 'Default', 'Secure Preferences');
      try { extensionId = extensionIdFromPreferences(await readFile(preferences, 'utf8'), extensionPath); }
      catch { /* The profile is still being written. */ }
      if (!extensionId) await delay(250);
    }
    if (!extensionId) throw new Error('The browser did not register the extension. Check that it built without errors.');
    console.log(`Extension ID: ${extensionId}`);

    // The target starts blank so the preview stub can be installed before the
    // popup module ever evaluates. Navigating first would run the real snapshot
    // request and the stub would arrive too late.
    const { targetId } = await cdp.send('Target.createTarget', { url: 'about:blank' });
    const { sessionId } = await cdp.send('Target.attachToTarget', { targetId, flatten: true });
    await cdp.send('Page.enable', {}, sessionId);
    if (values.preview) await cdp.send('Page.addScriptToEvaluateOnNewDocument', { source: previewStub() }, sessionId);
    await cdp.send('Runtime.enable', {}, sessionId);
    await cdp.send('Page.navigate', { url: `chrome-extension://${extensionId}/popup.html` }, sessionId);
    const exceptions = [];
    socket.addEventListener('message', event => {
      const message = JSON.parse(event.data);
      if (message.sessionId !== sessionId || message.method !== 'Runtime.exceptionThrown') return;
      const detail = message.params.exceptionDetails;
      exceptions.push((detail.exception?.description ?? detail.text ?? '').split('\n')[0]);
    });
    const readProbe = async () => {
      const result = await cdp.send('Runtime.evaluate', { expression: probeExpression, returnByValue: true }, sessionId);
      return result.result?.value ? JSON.parse(result.result.value) : null;
    };
    let probe = null;
    for (let attempt = 0; attempt < 60; attempt++) {
      probe = await readProbe();
      if (probe?.timerDisplay) break;
      await delay(250);
    }
    if (!probe) throw new Error('The popup did not render. Open it manually to inspect the console.');
    if (values.view) {
      const switched = await cdp.send('Runtime.evaluate', {
        expression: `(() => { const tab = document.querySelector('[data-view=${JSON.stringify(values.view)}]');
          if (!tab) return false; tab.click(); return true; })()`, returnByValue: true }, sessionId);
      if (switched.result?.value !== true) throw new Error(`Unknown view "${values.view}". Use one of: today, upcoming, inbox, completed, timer.`);
      await delay(400);
      probe = await readProbe();
    }
    const problems = auditProbe(probe);
    console.log('\nPopup rendered:');
    console.log(`  tabs          ${probe.tabs.join(', ')}`);
    console.log(`  timer         ${probe.timerDisplay} (${probe.timerPhase})`);
    console.log(`  presets       ${probe.presets.join(' | ')}`);
    console.log(`  delete button ${probe.deleteButton}`);
    console.log(`  task rows     ${probe.rows}`);
    console.log(`  signed out    ${probe.signedOut}`);
    for (const exception of exceptions) console.log(`  exception     ${exception}`);
    if (values.screenshot) {
      // The popup is designed for a 392px-wide panel, but a browser tab is much
      // wider. Resize the viewport to the popup's own width so the layout is
      // captured as it really appears, then clip to the rendered height.
      await cdp.send('Emulation.setDeviceMetricsOverride', { width: 392, height: 800, deviceScaleFactor: 2, mobile: false }, sessionId);
      await delay(250);
      const measured = await cdp.send('Runtime.evaluate', {
        expression: '({ height: document.body.scrollHeight })', returnByValue: true }, sessionId);
      const height = Math.max(measured.result?.value?.height ?? 600, 120);
      const shot = await cdp.send('Page.captureScreenshot', { format: 'png',
        clip: { x: 0, y: 0, width: 392, height, scale: 1 } }, sessionId);
      await cdp.send('Emulation.clearDeviceMetricsOverride', {}, sessionId);
      const { writeFile } = await import('node:fs/promises');
      await writeFile(path.resolve(values.screenshot), Buffer.from(shot.data, 'base64'));
      console.log(`\nScreenshot: ${path.resolve(values.screenshot)} (392x${height} at 2x)`);
    }
    if (problems.length) throw new Error(`The popup did not render as expected:\n  ${problems.join('\n  ')}`);
    if (values['no-open']) {
      console.log(`\nPopup rendered without problems. Open chrome-extension://${extensionId}/popup.html to sign in.`);
    } else if (values.await === undefined) {
      console.log(`\nPopup rendered without problems. To sign in manually, open: chrome-extension://${extensionId}/popup.html`);
      if (!values['keep-profile']) console.log('Stopping the browser. Sign-in needs a manual step, so add --keep-profile to keep the session.');
    } else {
      console.log(`\nHolding the browser open for ${values.await}s. Sign in at chrome-extension://${extensionId}/popup.html`);
      await delay(Number(values.await) * 1000);
    }
  } finally {
    if (socket) socket.close();
    await shutdown();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => { console.error(`Extension run failed: ${error.message}`); process.exitCode = 1; });
}
