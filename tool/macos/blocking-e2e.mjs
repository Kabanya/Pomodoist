#!/usr/bin/env node
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {createServer} from 'node:http';
import {createWriteStream} from 'node:fs';
import {mkdir, mkdtemp, readFile, readdir, realpath, writeFile, rm, access} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createInterface} from 'node:readline';
import {Processes, createControlServer} from './blocking-e2e-support.mjs';
import {build} from '../../apps/chrome-extension/build.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const artifacts = path.join(root, 'build/blocking-e2e', new Date().toISOString().replaceAll(':', '-'));
const fixtureApp = path.join(root, 'build/blocking-e2e/BlockingFixture.app');
const binary = path.join(fixtureApp, 'Contents/MacOS/blocking-fixture');
const processes = new Processes();
const token = randomBytes(32).toString('hex');
let temporary, targetExecutable, context, browserLaunching, control, website, fixture, flutter, interrupted;
let step = 'preflight';
const logs = [];
const pending = new Map();
let serial = 0, appPid;
const abort = new AbortController();
const timeout = setTimeout(() => abort.abort(Error('E2E exceeded the 15-minute overall deadline')), 15 * 60 * 1000);
const onSignal = signal => abort.abort(Error(`Interrupted by ${signal}`));
const sigint = () => onSignal('SIGINT'), sigterm = () => onSignal('SIGTERM');
process.once('SIGINT', sigint); process.once('SIGTERM', sigterm);

function logged(command, args, name, options = {}) {
  abort.signal.throwIfAborted();
  const child = processes.start(command, args, {cwd: root, ...options});
  const log = createWriteStream(path.join(artifacts, `${name}.log`)); logs.push(log);
  child.stdout?.pipe(log, {end: false}); child.stderr?.pipe(log, {end: false});
  return child;
}

async function run(command, args, name, options) {
  const child = logged(command, args, name, options);
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  const result = await child.done;
  if (result.code !== 0) throw result.error ?? Error(`${name} failed (${result.code}); see ${artifacts}/${name}.log`);
  return output;
}

async function native(command) {
  const id = ++serial;
  const result = new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(Error(`Native step ${command.step} timed out`)); }, 20000);
    pending.set(id, {resolve, reject, timer});
  });
  fixture.stdin.write(JSON.stringify({id, ...command}) + '\n');
  return result;
}

async function browserBefore(port, code) {
  const worker = context.serviceWorkers()[0] ?? await context.waitForEvent('serviceworker');
  const extensionId = new URL(worker.url()).host;
  const popup = await context.newPage();
  await popup.goto(`chrome-extension://${extensionId}/popup.html`);
  await popup.waitForFunction(() => document.getElementById('startup').hidden);
  await popup.getByText('Pair desktop for offline Focus', {exact: true}).click();
  await popup.locator('#bridge-port').fill(String(port));
  await popup.locator('#pair-code').fill(code);
  await popup.locator('#pair-form button[type="submit"]').click();
  await popup.waitForFunction(() => document.getElementById('pair-code').value === '' && document.getElementById('focus-source').value === 'desktop');
  await popup.locator('#enable-protection').check();
  await popup.waitForFunction(() => document.getElementById('protection-status').textContent.includes('protection idle'));
  const address = `http://blocked.blocking.test:${website.address().port}`;
  const allowedAddress = `http://allowed.blocked.blocking.test:${website.address().port}`;
  const loaded = await context.newPage();
  await loaded.goto(address + '/loaded');
  await loaded.locator('#draft').fill('keep browser draft');
  const allowed = await context.newPage();
  await allowed.goto(allowedAddress + '/exception');
  assert.equal(await allowed.locator('#draft').inputValue(), 'initial');
  return {popup, extensionId, loaded, allowed, address, allowedAddress};
}

let browser;
async function browserBlocked() {
  await browser.popup.waitForFunction(() => document.getElementById('protection-status').textContent.includes('Website protection active'));
  await browser.loaded.waitForFunction(() => [...document.querySelectorAll('div')].some(d => d.style.zIndex === '2147483647'));
  await browser.loaded.bringToFront();
  await browser.loaded.keyboard.type('blocked typing');
  assert.equal(await browser.loaded.locator('#draft').inputValue(), 'keep browser draft');
  const fresh = await context.newPage();
  await fresh.goto(browser.address + '/new').catch(error => { if (!error.message.includes('ERR_BLOCKED_BY_CLIENT')) throw error; });
  await fresh.waitForURL(`chrome-extension://${browser.extensionId}/blocked.html`);
  await browser.allowed.reload();
  await browser.allowed.waitForFunction(() => ![...document.querySelectorAll('div')].some(d => d.style.zIndex === '2147483647'));
  await browser.allowed.locator('#draft').click();
  await browser.allowed.keyboard.press('End');
  await browser.allowed.keyboard.type(' allowed during Focus');
  assert.equal(await browser.allowed.locator('#draft').inputValue(), 'initial allowed during Focus');
}

async function browserAfter() {
  await browser.popup.waitForFunction(() => document.getElementById('protection-status').textContent.includes('protection idle'));
  await browser.loaded.waitForFunction(() => ![...document.querySelectorAll('div')].some(d => d.style.zIndex === '2147483647'));
  assert.equal(await browser.loaded.locator('#draft').inputValue(), 'keep browser draft');
  assert.equal(browser.loaded.url(), browser.address + '/loaded');
  await browser.loaded.locator('#draft').click();
  await browser.loaded.keyboard.press('End');
  await browser.loaded.keyboard.type(' restored');
  assert.equal(await browser.loaded.locator('#draft').inputValue(), 'keep browser draft restored');
  const page = await context.newPage(); await page.goto(browser.address + '/released');
  assert.equal(await page.locator('#draft').inputValue(), 'initial');
}

async function action(body) {
  abort.signal.throwIfAborted();
  step = body.step; console.log(`E2E: ${step}`);
  switch (step) {
    case 'register':
      await native({step: 'register', pid: body.pid});
      appPid = body.pid;
      await writeFile(path.join(artifacts, 'processes.json'), JSON.stringify({flutter: flutter.pid, native: fixture.pid, app: appPid, temporary}, null, 2));
      return {ok: true};
    case 'discover': return native({step: 'discover', pid: body.pid});
    case 'before':
      browser = await browserBefore(body.port, body.code);
      await native({step: 'before'});
      if (process.env.E2E_FAIL_AFTER === 'before') throw Error('Intentional cleanup test failure after before');
      return {ok: true};
    case 'blocked':
      await browserBlocked();
      return native({step: 'blocked'});
    case 'after':
      await browserAfter();
      return native({step: 'after'});
    default: throw Error(`Unknown E2E step: ${step}`);
  }
}

async function main() {
  if (process.platform !== 'darwin') throw Error('Blocking UI E2E requires macOS with an active desktop login');
  await mkdir(artifacts, {recursive: true});
  const flutterSdk = process.env.FLUTTER_BIN ?? path.join(root, '.fvm/flutter_sdk/bin/flutter');
  await access(flutterSdk).catch(() => { throw Error('Pinned Flutter SDK missing. Run fvm install or set FLUTTER_BIN.'); });
  const {chromium} = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
  await access(process.env.CHROME_BIN ?? chromium.executablePath()).catch(() => { throw Error('Playwright Chromium missing. Run playwright install chromium or set CHROME_BIN.'); });
  await run('xcrun', ['--find', 'swiftc'], 'xcode');
  await run('xcodebuild', ['-version'], 'xcode-version');
  await mkdir(path.dirname(binary), {recursive: true});
  await writeFile(path.join(fixtureApp, 'Contents/Info.plist'), `<?xml version="1.0"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict><key>CFBundleExecutable</key><string>blocking-fixture</string><key>CFBundleIdentifier</key><string>com.pomodoist.blocking-e2e.fixture</string><key>CFBundleName</key><string>Pomodoist Blocking Fixture</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>`);
  // Keep the helper path/signature stable across runs so macOS can retain consent.
  const source = await readFile(path.join(root, 'tool/macos/BlockingFixture.swift'), 'utf8');
  const stamp = path.join(root, 'build/blocking-e2e/BlockingFixture.source.swift');
  let previous = ''; try { previous = await readFile(stamp, 'utf8'); } catch {}
  if (previous !== source) {
    await run('xcrun', ['swiftc', '-parse-as-library', '-framework', 'AppKit', '-framework', 'ApplicationServices', path.join(root, 'tool/macos/BlockingFixture.swift'), '-o', binary], 'swift');
    await run('codesign', ['--force', '--sign', '-', fixtureApp], 'codesign');
    await writeFile(stamp, source);
  }
  const preflight = JSON.parse((await run(binary, ['--preflight'], 'native-preflight')).trim());
  await writeFile(path.join(artifacts, 'preflight.json'), JSON.stringify(preflight, null, 2));
  assert.ok(preflight.desktop, 'An unlocked console desktop login is required');
  assert.ok(preflight.accessibility && preflight.postEvents, `Grant Accessibility and event posting access to ${fixtureApp} (or the terminal launching it), then rerun. No permission dialogs are automated.`);
  if (process.argv.includes('--preflight')) { console.log('PASS blocking E2E prerequisites'); return; }
  temporary = await mkdtemp(path.join(tmpdir(), 'pomodoist-blocking-e2e-'));
  abort.signal.throwIfAborted();
  website = createServer((req, res) => {
    res.setHeader('Content-Type', 'text/html');
    res.end('<!doctype html><title>Blocking E2E fixture</title><input id="draft" value="initial">');
  });
  await new Promise(resolve => website.listen(0, '127.0.0.1', resolve));
  control = await createControlServer(token, action);
  const appDirectory = path.join(root, 'apps/flutter');
  step = 'build'; console.log('E2E: build isolated development application');
  await run(flutterSdk, ['build', 'macos', '--debug', '--no-pub', '--flavor', 'Development', '--target', 'integration_test/blocking_test.dart',
    `--dart-define=BLOCKING_E2E_URL=${control.url}`, `--dart-define=BLOCKING_E2E_TOKEN=${token}`], 'build', {cwd: appDirectory});
  const products = path.join(appDirectory, 'build/macos/Build/Products/Debug-Development');
  const apps = (await readdir(products)).filter(name => name.endsWith('.app'));
  assert.equal(apps.length, 1, 'Expected one development app build');
  const testApp = path.join(temporary, 'Pomodoist Blocking E2E.app');
  await run('ditto', [await realpath(path.join(products, apps[0])), testApp], 'copy-app');
  const plist = path.join(testApp, 'Contents/Info.plist');
  const executableName = (await run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleExecutable', plist], 'app-executable')).trim();
  targetExecutable = path.join(testApp, 'Contents/MacOS', executableName);
  await run('/usr/libexec/PlistBuddy', ['-c', 'Set :CFBundleIdentifier com.finchforge.pomodoist.dev.e2e', '-c', 'Set :CFBundleName Pomodoist Blocking E2E',
    '-c', 'Delete :CFBundleURLTypes', plist], 'app-identity');
  // The disposable app needs loopback and JIT, never the user's app groups,
  // credentials, microphone, Apple sign-in or associated domains.
  const entitlements = path.join(temporary, 'Entitlements.plist');
  await writeFile(entitlements, '<?xml version="1.0"?><plist version="1.0"><dict><key>com.apple.security.app-sandbox</key><true/><key>com.apple.security.network.client</key><true/><key>com.apple.security.network.server</key><true/><key>com.apple.security.cs.allow-jit</key><true/></dict></plist>');
  await run('codesign', ['--force', '--sign', '-', '--entitlements', entitlements, testApp], 'sign-test-app');
  const extension = path.join(temporary, 'extension');
  await build({SUPABASE_URL: 'https://api.example.test', WEB_APP_URL: 'https://tasks.example.test', SUPABASE_ANON_KEY: 'sb_publishable_e2e', APP_ENV: 'development'}, extension);
  const manifestPath = path.join(extension, 'manifest.json');
  const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
  manifest.host_permissions.push('http://*/*', 'https://*/*');
  await writeFile(manifestPath, JSON.stringify(manifest));
  abort.signal.throwIfAborted();
  browserLaunching = chromium.launchPersistentContext(path.join(temporary, 'chromium'), {
    channel: 'chromium', headless: false,
    // The runner owns signal cleanup; Playwright's handlers exit before finally.
    handleSIGINT: false, handleSIGTERM: false, handleSIGHUP: false,
    timeout: 30000,
    ...(process.env.CHROME_BIN ? {executablePath: process.env.CHROME_BIN} : {}),
    args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`,
      '--host-resolver-rules=MAP *.blocking.test 127.0.0.1', '--no-proxy-server'],
  });
  context = await browserLaunching;
  abort.signal.throwIfAborted();
  context.setDefaultTimeout(15000);
  await context.tracing.start({screenshots: true, snapshots: true});
  fixture = logged(binary, [`--target=${targetExecutable}`], 'native', {stdio: ['pipe', 'pipe', 'pipe']});
  const ready = new Promise((resolve, reject) => {
    fixture.done.then(() => {
      reject(Error('Native fixture exited'));
      for (const item of pending.values()) { clearTimeout(item.timer); item.reject(Error('Native fixture exited')); }
      pending.clear();
    });
    createInterface({input: fixture.stdout}).on('line', line => {
      let value; try { value = JSON.parse(line); } catch { return; }
      if (value.ready) resolve();
      const item = pending.get(value.id);
      if (item) {
        pending.delete(value.id); clearTimeout(item.timer);
        if (value.error) item.reject(Error(value.error)); else item.resolve(value.result);
      }
    });
  });
  await ready;
  flutter = logged(flutterSdk, ['drive', '--no-pub', '-d', 'macos', '--flavor', 'Development',
    '--driver=test_driver/integration_test.dart', '--target=integration_test/blocking_test.dart', `--use-application-binary=${testApp}`], 'flutter', {cwd: appDirectory});
  await writeFile(path.join(artifacts, 'processes.json'), JSON.stringify({flutter: flutter.pid, native: fixture.pid, temporary}, null, 2));
  const result = await flutter.done;
  assert.equal(result.code, 0, `Flutter UI E2E failed; see ${artifacts}/flutter.log`);
  assert.equal(step, 'after', 'The full blocking lifecycle did not run');
  console.log('PASS real UI: configuration, pairing, native keyboard shield, loaded/new browser pages, exception and release');
}

try {
  await Promise.race([main(), new Promise((_, reject) => {
    abort.signal.addEventListener('abort', () => reject(abort.signal.reason), {once: true});
  })]);
} catch (error) {
  interrupted = error;
  console.error(`FAIL ${step}: ${error.message}\nArtifacts: ${artifacts}`);
  process.exitCode = 1;
} finally {
  clearTimeout(timeout);
  process.removeListener('SIGINT', sigint); process.removeListener('SIGTERM', sigterm);
  context ??= await browserLaunching?.catch(() => undefined);
  if (interrupted && context) {
    for (const [i, page] of context.pages().entries()) {
      await page.screenshot({path: path.join(artifacts, `browser-${i}.png`), timeout: 2000}).catch(() => {});
    }
  }
  await context?.tracing.stop({path: path.join(artifacts, 'browser-trace.zip')}).catch(() => {});
  // Close Chromium before killing any Flutter/native process; only this temporary profile is owned here.
  await context?.close().catch(() => {});
  // macOS sandboxing can put Runner outside Flutter's process group. Its PID
  // was registered by the test before mounting any UI and verified by AppKit.
  if (fixture && targetExecutable) await native({step: 'cleanup'}).catch(error => {
    console.error(`Owned Runner cleanup failed: ${error.message}`); process.exitCode = 1;
  });
  for (const item of pending.values()) { clearTimeout(item.timer); item.reject(Error('E2E shutting down')); }
  pending.clear();
  await control?.close();
  await processes.close();
  if (website) { website.closeAllConnections(); await new Promise(resolve => website.close(resolve)); }
  if (temporary) await rm(temporary, {recursive: true, force: true});
  await Promise.all(logs.map(log => new Promise(resolve => log.end(resolve))));
}
