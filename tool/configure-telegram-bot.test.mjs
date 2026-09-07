import { test } from 'node:test';
import assert from 'node:assert/strict';
import { configureTelegramBot, telegramConfiguration } from './configure-telegram-bot.mjs';
const env = { POMODOIST_TELEGRAM_BOT_TOKEN: '123:TEST', POMODOIST_TELEGRAM_WEBHOOK_SECRET: 's'.repeat(48),
  SUPABASE_PUBLIC_URL: 'https://api.example.com', POMODOIST_WEB_URL: 'https://app.example.com' };
test('setup preserves pending updates and verifies the webhook', async () => {
  const requests = [];
  await configureTelegramBot(env, async (url, init) => {
    const method = url.split('/').at(-1), body = JSON.parse(init.body); requests.push({ method, body });
    return Response.json({ ok: true, result: method === 'getWebhookInfo' ? { url: telegramConfiguration(env).webhook } : true });
  });
  const hook = requests.find(r => r.method === 'setWebhook').body;
  assert.equal(hook.drop_pending_updates, false); assert.deepEqual(hook.allowed_updates, ['message', 'callback_query']);
  assert.equal(hook.secret_token, env.POMODOIST_TELEGRAM_WEBHOOK_SECRET);
  assert.equal(requests.filter(r => r.method === 'setMyCommands').length, 2);
  for (const request of requests.filter(r => r.method === 'setMyCommands')) assert.deepEqual(request.body.commands.map(c => c.command), ['start']);
});
test('setup refuses insecure URLs and absent/weak secrets before network access', () => {
  for (const patch of [{ POMODOIST_TELEGRAM_WEBHOOK_SECRET: '' }, { SUPABASE_PUBLIC_URL: 'http://example.com' },
    { POMODOIST_WEB_URL: 'https://user:pass@app.example.com' }, { POMODOIST_TELEGRAM_TIME_ZONE: 'Invalid/Zone' }]) {
    assert.throws(() => telegramConfiguration({ ...env, ...patch }));
  }
});
test('setup errors never contain the token', async () => {
  await assert.rejects(configureTelegramBot(env, async () => { throw new Error(env.POMODOIST_TELEGRAM_BOT_TOKEN); }), error => !error.message.includes('123:TEST'));
});
test('profile checks bot identity before changing settings', async () => {
  for (const username of ['pomodoist_bot', 'pomodoist_test_bot']) {
    const methods = [];
    const result = configureTelegramBot({ ...env, POMODOIST_TELEGRAM_BOT_USERNAME: 'pomodoist_test_bot' }, async (url) => {
      const method = url.split('/').at(-1); methods.push(method);
      return Response.json({ ok: true, result: method === 'getMe' ? { username } :
        method === 'getWebhookInfo' ? { url: telegramConfiguration(env).webhook } : true });
    });
    if (username === 'pomodoist_bot') {
      await assert.rejects(result, /does not match/);
      assert.deepEqual(methods, ['getMe']);
    } else {
      await result;
      assert.equal(methods[0], 'getMe');
      assert.ok(methods.includes('setWebhook'));
    }
  }
});
