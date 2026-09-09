import { createServer } from 'node:http';
import { readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { parseArgs } from 'node:util';
import { pathToFileURL } from 'node:url';
import path from 'node:path';
import { root, miniAppFiles, loadEnv, runtimeConfig, configScript, openUrl } from './web-companions.mjs';
import { telegramApi } from './configure-telegram-bot.mjs';

const apiPath = '/functions/v1/pomodoist-telegram', limit = 48 * 1024;
const source = path.join(root, 'telegram-mini-app');

export function createPreviewServer(config, { sourceDir = source, allowedOrigins = new Set(), fetcher = fetch } = {}) {
  const server = createServer(async (req, res) => {
    const reply = (status, body, headers = {}) => {
      res.writeHead(status, { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...headers });
      res.end(req.method === 'HEAD' ? undefined : body);
    };
    const failure = (status, code) => reply(status, JSON.stringify({ ok: false, code }), { 'Content-Type': 'application/json' });
    try {
      const url = new URL(req.url, 'http://localhost');
      if (url.pathname === apiPath) {
        if (!allowedOrigins.has(req.headers.origin)) return failure(403, 'origin_forbidden');
        if (req.method !== 'POST') return failure(405, 'method_not_allowed');
        if (Number(req.headers['content-length'] ?? 0) > limit) { req.resume(); return failure(413, 'body_too_large'); }
        const body = await new Promise((resolve, reject) => {
          const chunks = []; let size = 0;
          req.on('data', chunk => {
            size += chunk.length;
            if (size > limit) reject(Object.assign(new Error(), { status: 413 }));
            else chunks.push(chunk);
          });
          req.on('end', () => resolve(Buffer.concat(chunks)));
          req.on('error', reject);
        });
        const headers = { 'Content-Type': 'application/json', Origin: config.webAppUrl, apikey: config.supabaseAnonKey,
          'X-Telegram-Init-Data': req.headers['x-telegram-init-data'] ?? '' };
        if (req.headers.authorization) headers.Authorization = req.headers.authorization;
        const upstream = await fetcher(config.supabaseUrl + apiPath, {
          method: 'POST', headers, body, redirect: 'error', signal: AbortSignal.timeout(15000),
        });
        return reply(upstream.status, Buffer.from(await upstream.arrayBuffer()), { 'Content-Type': 'application/json' });
      }
      if (!['GET', 'HEAD'].includes(req.method)) return failure(405, 'method_not_allowed');
      if (url.pathname === '/') return reply(302, '', { Location: config.webAppUrl + '/' });
      if (url.pathname === '/telegram') return reply(302, '', { Location: '/telegram/' });
      if (url.pathname === '/config.js') return reply(200, configScript({ ...config, supabaseUrl: '' }), { 'Content-Type': 'text/javascript' });
      const file = url.pathname === '/telegram/' ? 'index.html' : url.pathname.slice('/telegram/'.length);
      if (!url.pathname.startsWith('/telegram/') || !miniAppFiles.includes(file)) return failure(404, 'not_found');
      const type = file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : 'text/html';
      return reply(200, await readFile(path.join(sourceDir, file)), { 'Content-Type': type + '; charset=utf-8' });
    } catch (error) {
      if (!res.headersSent) failure(error.status === 413 ? 413 : 503, error.status === 413 ? 'body_too_large' : 'request_failed');
      else res.end();
    }
  });
  server.requestTimeout = 15000;
  return server;
}

async function debugBot(call) {
  const bot = await call('getMe', {});
  if (bot?.username !== 'pomodoist_test_bot') throw new Error('Debug requires @pomodoist_test_bot. No settings changed.');
  return bot.id;
}
export async function restoreDebugMenu(call, stateFile) {
  let state;
  try { state = JSON.parse(await readFile(stateFile, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return; throw error; }
  if (state.botId !== await debugBot(call)) throw new Error('Saved debug menu belongs to a different bot.');
  const current = await call('getChatMenuButton', {});
  if (current?.web_app?.url === state.debugUrl) await call('setChatMenuButton', { menu_button: state.menu });
  await rm(stateFile);
}
export async function activateDebugMenu(call, stateFile, debugUrl) {
  const botId = await debugBot(call);
  await restoreDebugMenu(call, stateFile);
  const menu = await call('getChatMenuButton', {});
  await mkdir(path.dirname(stateFile), { recursive: true });
  // Write before the request: a lost response must still be recoverable.
  await writeFile(stateFile, JSON.stringify({ botId, menu, debugUrl }), { mode: 0o600, flag: 'wx' });
  await call('setChatMenuButton', { menu_button: { type: 'web_app', text: 'Pomodoist Debug', web_app: { url: debugUrl } } });
  const current = await call('getChatMenuButton', {});
  if (current?.web_app?.url !== debugUrl) throw new Error('Telegram debug menu verification failed.');
}

export function readTunnelUrl(child, timeoutMs = 30000) {
  return new Promise((resolve, reject) => {
    let output = '';
    const finish = (error, url) => {
      clearTimeout(timer); child.stderr.off('data', data); child.off('error', failed); child.off('exit', exited);
      child.stderr.resume();
      error ? reject(error) : resolve(url);
    };
    const failed = () => finish(new Error('Cannot start cloudflared. Install it with: brew install cloudflared'));
    const exited = () => finish(new Error('Cloudflare tunnel exited before becoming ready.'));
    const data = chunk => {
      output = (output + chunk.toString()).slice(-16384);
      const match = output.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com\b/);
      if (match) finish(null, match[0]);
    };
    const timer = setTimeout(() => finish(new Error('Cloudflare tunnel startup timed out.')), timeoutMs);
    child.stderr.on('data', data); child.once('error', failed); child.once('exit', exited);
  });
}

async function main() {
  const { values } = parseArgs({ options: { config: { type: 'string', default: path.join(root, '.env.staging') },
    'bot-config': { type: 'string', default: path.join(root, '.env.telegram.staging') }, 'no-open': { type: 'boolean' } } });
  const env = await loadEnv(values.config), botEnv = await loadEnv(values['bot-config']);
  if (env.POMODOIST_ENVIRONMENT !== 'staging') throw new Error('telegram-debug requires a staging profile.');
  const config = runtimeConfig(env);
  if (config.supabaseUrl !== botEnv.SUPABASE_URL || config.webAppUrl !== botEnv.POMODOIST_WEB_URL) {
    throw new Error('Staging app and bot profiles must use the same backend and web origin.');
  }
  const call = telegramApi(botEnv.POMODOIST_TELEGRAM_BOT_TOKEN);
  const stateFile = path.join(root, 'build/telegram/debug/menu.json');
  const logFile = path.join(root, 'build/telegram/debug/tunnel.log');
  const origins = new Set(), server = createPreviewServer(config, { allowedOrigins: origins });
  let child, ownsServer = false, stopping = false;
  let stop;
  const stopped = new Promise(resolve => { stop = () => { stopping = true; resolve(); }; });
  process.on('SIGINT', stop); process.on('SIGTERM', stop);
  try {
    server.listen(7359, '127.0.0.1'); await once(server, 'listening'); ownsServer = true;
    await debugBot(call);
    await restoreDebugMenu(call, stateFile);
    if (stopping) return;
    await mkdir(path.dirname(logFile), { recursive: true });
    await writeFile(logFile, '', { mode: 0o600 });
    console.log(`Starting HTTPS tunnel. Log: ${logFile}`);
    child = spawn('cloudflared', ['tunnel', '--no-autoupdate', '--grace-period', '1s', '--loglevel', 'info', '--logfile', logFile,
      '--url', 'http://127.0.0.1:7359'], { stdio: ['ignore', 'ignore', 'pipe'] });
    const origin = await Promise.race([readTunnelUrl(child), stopped.then(() => null)]);
    if (stopping || !origin) return;
    origins.add(origin);
    // The URL is printed before the connector is ready; verify the public route first.
    let ready = false;
    for (let attempt = 0; attempt < 10 && !stopping && child.exitCode === null; attempt++) {
      try {
        const response = await fetch(origin + '/telegram/app.js', { signal: AbortSignal.timeout(5000) });
        ready = response.ok && await response.text() === await readFile(path.join(source, 'app.js'), 'utf8');
      } catch { /* A new tunnel may need a moment for DNS and connection setup. */ }
      if (ready) break;
      await Promise.race([new Promise(resolve => setTimeout(resolve, 1000)), stopped]);
    }
    if (stopping) return;
    if (!ready || child.exitCode !== null) throw new Error(`Cloudflare public preview is unavailable. The bot menu was not changed. Check DNS/network connectivity and ${logFile}`);
    await activateDebugMenu(call, stateFile, origin + '/telegram/');
    if (stopping) return;
    console.log(`Mini App (staging): ${origin}/telegram/`);
    console.log('Open https://t.me/pomodoist_test_bot and press Pomodoist Debug in the chat menu.');
    console.log('Refresh the Mini App after editing files. Ctrl+C restores the previous bot menu.');
    if (!values['no-open']) await openUrl('https://t.me/pomodoist_test_bot');
    child.once('exit', () => { if (!stopping) { console.error('Cloudflare tunnel stopped.'); process.exitCode = 1; stop(); } });
    if (child.exitCode !== null) stop();
    await stopped;
  } finally {
    try { if (ownsServer) await restoreDebugMenu(call, stateFile); }
    catch { console.error('Menu restoration failed. State was retained; run make telegram-debug again to recover.'); process.exitCode = 1; }
    child?.kill(); server.closeAllConnections(); server.close();
    process.off('SIGINT', stop); process.off('SIGTERM', stop);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => { console.error(error.code === 'EADDRINUSE' ? 'Port 7359 is already in use. Stop the existing preview first.' : error.message); process.exitCode = 1; });
}
