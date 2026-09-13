import { config } from './config.js';
import { Store, synchronize } from './sync.js';
import { Client } from './client.js';

const store = new Store(chrome.storage.local, config.apiUrl);
const ready = (async () => {
  await chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' });
  await store.init();
})();
const client = new Client(config, store);
let tail = Promise.resolve();
const notify = () => chrome.runtime.sendMessage({ event: 'state', snapshot: store.snapshot() }).catch(() => {});
const sync = async () => { try { await synchronize(store, client, notify); } catch { /* Error is persisted and shown next time the popup opens. */ } };

async function dispatch(message) {
  const p = message.payload ?? {};
  switch (message.type) {
    case 'sync': await sync(); break;
    case 'mutate': await store.enqueue(p.action, p.owner); notify(); await sync(); break;
    case 'password': {
      if (store.data.session) throw new Error('Sign out before switching accounts.');
      if (typeof p.email !== 'string' || !p.email.trim() || p.email.length > 320 || typeof p.password !== 'string' || !p.password || p.password.length > 4096) {
        throw new Error('Enter your email and password.');
      }
      const captcha = config.captchaEnabled ? await client.captcha(chrome.identity) : undefined;
      await store.acceptSession(await client.password(p.email, p.password, captcha));
      notify(); await sync(); break;
    }
    case 'oauth':
      if (store.data.session) throw new Error('Sign out before switching accounts.');
      await store.acceptSession(await client.oauth(p.provider, chrome.identity));
      notify(); await sync(); break;
    case 'logout': {
      const token = store.data.session?.access_token;
      await store.logout(p.discard === true); notify();
      if (token) {
        try { await client.raw('/auth/v1/logout?scope=local', {}, token, true); }
        catch { await store.save({ error: 'Signed out on this device. Server session revocation could not be confirmed.' }); }
      }
      break;
    }
    case 'realtime':
      return { apiUrl: config.apiUrl, anonKey: config.anonKey, accessToken: await client.token(),
        userId: store.data.owner, deviceId: store.data.deviceId };
    default: throw new Error('Unknown extension command.');
  }
  notify();
  return store.snapshot();
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (message?.event) return false;
  // No content scripts or external messaging. Only our packaged popup can read
  // private account state or trigger an authenticated request.
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL('popup.html')) return false;
  if (message?.type === 'snapshot') {
    ready.then(() => respond({ ok: true, value: store.snapshot() }), () => respond({ ok: false, error: 'Cannot open local extension storage.' }));
    return true;
  }
  const run = tail.then(async () => { await ready; return dispatch(message); });
  tail = run.catch(() => {});
  run.then(value => respond({ ok: true, value }), async error => {
    const message = error?.message || 'The operation failed. Please retry.';
    if (store.data) { try { await store.save({ error: message }); notify(); } catch { /* Storage may be full. */ } }
    respond({ ok: false, error: message });
  });
  return true;
});
