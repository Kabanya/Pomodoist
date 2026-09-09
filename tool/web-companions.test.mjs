import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm, readdir } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { build } from '../chrome-extension/build.mjs';
import { buildMiniApp, runtimeConfig } from './web-companions.mjs';
import { createPreviewServer, activateDebugMenu, restoreDebugMenu, readTunnelUrl } from './telegram-debug.mjs';

const env = { POMODOIST_ENVIRONMENT: 'staging', SUPABASE_URL: 'https://api.example.test',
  WEB_APP_URL: 'https://app.example.test', SUPABASE_ANON_KEY: 'sb_publishable_test',
  POMODOIST_TELEGRAM_BOT_TOKEN: '123:PRIVATE', PRIVATE_VALUE: 'never-publish-this' };
const temporary = async t => {
  const dir = await mkdtemp(path.join(tmpdir(), 'pomodoist-companions-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  return dir;
};

test('both builds isolate outputs and publish only public configuration', async t => {
  const dir = await temporary(t), debug = path.join(dir, 'debug'), release = path.join(dir, 'release');
  assert.equal(await build(env, debug), debug);
  await writeFile(path.join(debug, 'keep.txt'), 'debug');
  await build({ ...env, WEB_APP_URL: 'https://release.example.test' }, release);
  assert.equal(await readFile(path.join(debug, 'keep.txt'), 'utf8'), 'debug');
  assert.match(await readFile(path.join(release, 'src/config.js'), 'utf8'), /release\.example\.test/);
  const mini = path.join(dir, 'mini');
  await buildMiniApp({ ...env, POMODOIST_ENVIRONMENT: 'production' }, mini);
  assert.deepEqual((await readdir(path.join(mini, 'telegram'))).sort(), ['app.js', 'core.js', 'index.html', 'styles.css']);
  for (const file of [path.join(debug, 'src/config.js'), path.join(mini, 'config.js')]) {
    assert.doesNotMatch(await readFile(file, 'utf8'), /PRIVATE|never-publish-this/);
  }
  assert.throws(() => runtimeConfig({ ...env, SUPABASE_ANON_KEY: 'invalid' }), /public/);
});

test('preview serves fresh allowlisted assets, redirects the full app and bounds its API proxy', async t => {
  const dir = await temporary(t);
  await writeFile(path.join(dir, 'app.js'), 'first');
  await writeFile(path.join(dir, '.env'), 'secret');
  const requests = [], origins = new Set(['https://preview.trycloudflare.com']);
  const server = createPreviewServer(runtimeConfig(env), { sourceDir: dir, allowedOrigins: origins,
    fetcher: async (url, options) => {
      requests.push({ url, options });
      return Response.json({ ok: false, code: 'invalid_init_data' }, { status: 401 });
    } });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const base = `http://127.0.0.1:${server.address().port}`;
  const runtime = await (await fetch(`${base}/config.js`)).text();
  assert.match(runtime, /"supabaseUrl":""/);
  assert.doesNotMatch(runtime, /PRIVATE|never-publish-this/);
  let response = await fetch(`${base}/telegram/app.js`);
  assert.equal(await response.text(), 'first'); assert.equal(response.headers.get('cache-control'), 'no-store');
  await writeFile(path.join(dir, 'app.js'), 'second');
  assert.equal(await (await fetch(`${base}/telegram/app.js`)).text(), 'second');
  for (const route of ['/.env', '/telegram/.env', '/telegram/core_test.ts', '/src/app.js', '/functions/v1/other', '/telegram/%2e%2e/%2eenv']) {
    assert.equal((await fetch(base + route)).status, 404, route);
  }
  response = await fetch(base, { redirect: 'manual' });
  assert.equal(response.headers.get('location'), 'https://app.example.test/');
  const api = `${base}/functions/v1/pomodoist-telegram`, body = JSON.stringify({ action: 'snapshot' });
  const headers = { origin: 'https://preview.trycloudflare.com', 'content-type': 'application/json',
    'x-telegram-init-data': 'real-signed-data', apikey: 'sb_publishable_test', 'x-telegram-bot-api-secret-token': 'do-not-forward' };
  response = await fetch(api, { method: 'POST', headers, body });
  assert.equal(response.status, 401);
  assert.equal((await response.json()).code, 'invalid_init_data');
  assert.equal(requests[0].url, 'https://api.example.test/functions/v1/pomodoist-telegram');
  assert.equal(requests[0].options.headers.Origin, 'https://app.example.test');
  assert.equal(requests[0].options.headers['X-Telegram-Init-Data'], 'real-signed-data');
  assert.equal(requests[0].options.headers['x-telegram-bot-api-secret-token'], undefined);
  assert.equal(requests[0].options.body.toString(), body);
  assert.equal((await fetch(api, { method: 'POST', headers: { ...headers, origin: 'https://other.test' }, body })).status, 403);
  assert.equal((await fetch(api, { method: 'POST', headers, body: 'x'.repeat(48 * 1024 + 1) })).status, 413);
  assert.equal(requests.length, 1);
  const competitor = createPreviewServer(runtimeConfig(env));
  competitor.listen(server.address().port, '127.0.0.1');
  assert.equal((await once(competitor, 'error'))[0].code, 'EADDRINUSE');
});

test('menu changes are restricted to the test bot and recover after an interrupted run', async t => {
  const dir = await temporary(t), stateFile = path.join(dir, 'menu.json');
  const original = { type: 'web_app', text: 'Pomodoist', web_app: { url: 'https://app.example.test/telegram/' } };
  let menu = structuredClone(original), username = 'pomodoist_bot', failRestore = false;
  const methods = [];
  const call = async (method, body) => {
    methods.push(method);
    if (method === 'getMe') return { id: 123, username };
    if (method === 'getChatMenuButton') return structuredClone(menu);
    if (method === 'setChatMenuButton') {
      if (failRestore && body.menu_button.text === 'Pomodoist') throw new Error('offline');
      menu = structuredClone(body.menu_button); return true;
    }
    assert.fail(`Unexpected Telegram method: ${method}`);
  };
  await assert.rejects(activateDebugMenu(call, stateFile, 'https://first.trycloudflare.com/telegram/'), /pomodoist_test_bot/);
  assert.deepEqual(menu, original);
  username = 'pomodoist_test_bot';
  await activateDebugMenu(call, stateFile, 'https://first.trycloudflare.com/telegram/');
  assert.equal(menu.text, 'Pomodoist Debug');
  assert.doesNotMatch(await readFile(stateFile, 'utf8'), /PRIVATE/);
  failRestore = true;
  await assert.rejects(restoreDebugMenu(call, stateFile), /offline/);
  assert.ok(await readFile(stateFile, 'utf8'));
  failRestore = false;
  await activateDebugMenu(call, stateFile, 'https://second.trycloudflare.com/telegram/');
  await restoreDebugMenu(call, stateFile);
  assert.deepEqual(menu, original);
  await assert.rejects(readFile(stateFile), { code: 'ENOENT' });
  assert.ok(methods.every(method => ['getMe', 'getChatMenuButton', 'setChatMenuButton'].includes(method)));
  await activateDebugMenu(call, stateFile, 'https://third.trycloudflare.com/telegram/');
  menu = { type: 'commands' };
  await restoreDebugMenu(call, stateFile);
  assert.deepEqual(menu, { type: 'commands' }, 'preserve a menu changed by another operator');
});

test('tunnel discovery handles split output, failed startup and timeout', async () => {
  for (const [script, expected] of [
    ["process.stderr.write('https://example.'); setTimeout(() => process.stderr.write('trycloudflare.com\\n'), 10); setInterval(() => {}, 1000)", 'https://example.trycloudflare.com'],
    ['process.exit(1)', /tunnel/i],
    ['setInterval(() => {}, 1000)', /timed out/i],
  ]) {
    const child = spawn(process.execPath, ['-e', script], { stdio: ['ignore', 'ignore', 'pipe'] });
    try {
      const result = readTunnelUrl(child, 250);
      if (typeof expected === 'string') assert.equal(await result, expected);
      else await assert.rejects(result, expected);
    } finally { child.kill(); }
  }
});
