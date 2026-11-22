// Run with Playwright installed, or point PLAYWRIGHT_MODULE at its ESM entry.
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createServer } from 'node:http';
import { after, test } from 'node:test';

const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const worker = await readFile(new URL('../../../apps/flutter/web/custom_model_worker.js', import.meta.url));
const nginx = await readFile(new URL('./nginx.conf', import.meta.url), 'utf8');
const workerLocation = nginx.split('location = /custom_model_worker.js {')[1].split('}')[0];
const workerPolicy = workerLocation.match(/add_header Content-Security-Policy "([^"]+)"/)[1];
const pageHeaders = await readFile(new URL('./security-headers.conf.template', import.meta.url), 'utf8');
// Supply test values for nginx/runtime placeholders in the shipped page policy.
const pagePolicy = pageHeaders.match(/add_header Content-Security-Policy "([^"]+)"/)[1]
  .replace(/__\w+__/g, 'https://managed.example')
  .replace('$pomodoist_frame_ancestors', "'self'")
  .replace('$pomodoist_telegram_script_origin', '');

async function listen(handler) {
  const server = createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  after(() => {
    server.closeAllConnections();
    return new Promise(resolve => server.close(resolve));
  });
  return `http://127.0.0.1:${server.address().port}`;
}

test('direct worker honors page CSP, CORS, redirect and credential boundaries', async () => {
  const app = await listen((request, response) => {
    if (request.url === '/custom_model_worker.js') {
      response.setHeader('Content-Type', 'application/javascript');
      response.setHeader('Content-Security-Policy', workerPolicy);
      response.end(worker);
    } else {
      response.setHeader('Content-Type', 'text/html');
      response.setHeader('Content-Security-Policy', pagePolicy);
      response.end('<!doctype html><title>App origin</title>');
    }
  });
  const calls = [];
  const provider = await listen(async (request, response) => {
    calls.push({ path: request.url, method: request.method, headers: request.headers });
    if (request.url.startsWith('/cors-denied/')) {
      response.end();
      return;
    }
    response.setHeader('Access-Control-Allow-Origin', app);
    response.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
    response.setHeader('Access-Control-Allow-Methods', 'POST');
    if (request.method === 'OPTIONS') {
      response.end();
    } else if (request.url.startsWith('/redirect/')) {
      response.writeHead(307, { Location: '/unexpected-target' }).end();
    } else {
      response.end('model reply');
    }
  });
  const browser = await chromium.launch({
    ...(process.env.CHROME_BIN && { executablePath: process.env.CHROME_BIN }),
  });
  try {
    const page = await browser.newPage();
    await page.goto(app);
    const endpoint = provider + '/v1/chat/completions';
    assert.equal(await page.evaluate(async url => {
      try { await fetch(url); return 'allowed'; } catch { return 'blocked'; }
    }, endpoint), 'blocked');
    assert.equal(calls.length, 0);
    const send = url => page.evaluate(url => new Promise((resolve, reject) => {
      const worker = new Worker('/custom_model_worker.js');
      worker.onmessage = event => { worker.terminate(); resolve(event.data); };
      worker.onerror = () => { worker.terminate(); reject(new Error('Worker failed')); };
      worker.postMessage({ url, body: '{"model":"test"}', key: 'test-only-token' });
    }), url);
    assert.deepEqual(await send(endpoint), { status: 200, body: 'model reply' });
    assert.deepEqual(calls.map(call => call.method), ['OPTIONS', 'POST']);
    assert.equal(calls[1].headers.authorization, 'Bearer test-only-token');
    assert.equal(calls[1].headers.cookie, undefined);
    assert.equal(calls[1].headers.referer, undefined);
    assert.deepEqual(await send(provider + '/cors-denied/chat/completions'), {});
    assert.deepEqual(await send(provider + '/redirect/chat/completions'), {});
    assert.ok(calls.every(call => call.path !== '/unexpected-target'));
    const before = calls.length;
    assert.deepEqual(await send('http://outside.example/v1/chat/completions'), {});
    assert.equal(calls.length, before);
  } finally {
    await browser.close();
  }
});
