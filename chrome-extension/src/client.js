import { APP_ID, callbackValue } from './core.js';
const b64url = bytes => btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
export const nonce = () => b64url(crypto.getRandomValues(new Uint8Array(32)));
export async function pkce() {
  const verifier = nonce();
  const challenge = b64url(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(verifier))));
  return { verifier, challenge };
}
class ApiError extends Error {
  constructor(status, auth) {
    super(status === 401 ? 'Session expired. Sign in again.' : status === 403 ? 'The account is not permitted to perform this action.' :
      status === 429 ? 'Too many requests. Wait briefly and retry.' : auth ? 'Sign-in failed. Check your credentials, verification and server configuration.' :
        'Server request failed. Pending changes are kept; retry later.');
    this.status = status;
  }
}
export class Client {
  constructor(config, store, fetcher = fetch.bind(globalThis)) {
    this.config = config; this.store = store; this.fetcher = fetcher; this.refreshing = null;
  }
  async raw(path, body, token, auth = false) {
    let response;
    try {
      response = await this.fetcher(`${this.config.apiUrl}${path}`, {
        method: 'POST', headers: { apikey: this.config.anonKey, 'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}) },
        body: JSON.stringify(body), signal: AbortSignal.timeout(12000), redirect: 'error', credentials: 'omit', cache: 'no-store',
      });
    } catch { throw new Error('Cannot reach the server. Check your connection and retry.'); }
    if (!response.ok) throw new ApiError(response.status, auth);
    if (response.status === 204) return null;
    const text = await response.text();
    if (!text) return null;
    try { return JSON.parse(text); } catch { throw new Error('Invalid server response.'); }
  }
  normalize(session) {
    return { access_token: session.access_token, refresh_token: session.refresh_token,
      expires_at: Number(session.expires_at ?? (Date.now() / 1000 + Number(session.expires_in))),
      user: { id: session.user?.id, email: session.user?.email ?? '' } };
  }
  async password(email, password, captchaToken) {
    const result = await this.raw('/auth/v1/token?grant_type=password', {
      email: email.trim(), password, ...(captchaToken ? { gotrue_meta_security: { captcha_token: captchaToken } } : {}),
    }, null, true);
    return this.normalize(result);
  }
  async token(force = false) {
    const session = this.store.data.session;
    if (!session) throw new Error('Sign in to your Pomodoist account.');
    if (!force && session.expires_at * 1000 > Date.now() + 60000) return session.access_token;
    if (!this.refreshing) this.refreshing = this.refresh(session).finally(() => { this.refreshing = null; });
    return this.refreshing;
  }
  async refresh(session) {
    try {
      const result = this.normalize(await this.raw('/auth/v1/token?grant_type=refresh_token', { refresh_token: session.refresh_token }, null, true));
      if (result.user.id !== this.store.data.owner) throw new Error('Account changed during session refresh.');
      await this.store.acceptSession(result);
      return result.access_token;
    } catch (error) {
      if (error.status === 400 || error.status === 401) await this.store.save({ session: null, error: 'Session expired. Sign in again to sync pending changes.' });
      throw error;
    }
  }
  async authorized(path, body) {
    try { return await this.raw(path, body, await this.token()); }
    catch (error) {
      if (error.status !== 401) throw error;
      try { return await this.raw(path, body, await this.token(true)); }
      catch (retryError) {
        if (retryError.status === 401) await this.store.save({ session: null });
        throw retryError;
      }
    }
  }
  rpc(name, body = {}) {
    if (!['push_changes', 'pull_changes', 'get_account_overview'].includes(name)) throw new Error('Unsupported API call.');
    return this.authorized(`/rest/v1/rpc/${name}`, body);
  }
  overview() { return this.rpc('get_account_overview'); }
  async broadcast() {
    // A rejected best-effort hint must not invalidate the Auth session.
    return this.raw('/realtime/v1/api/broadcast', { messages: [{
      topic: `sync:${this.store.data.owner}:${APP_ID}`, event: 'changed', private: true,
      payload: { appId: APP_ID, deviceId: this.store.data.deviceId, sentAt: new Date().toISOString() },
    }] }, await this.token());
  }
  async oauth(provider, identity) {
    if (!['google', 'apple'].includes(provider)) throw new Error('Unsupported sign-in provider.');
    const started = Date.now(), state = nonce(), { verifier, challenge } = await pkce();
    const redirect = identity.getRedirectURL('auth-callback');
    const target = new URL(redirect); target.searchParams.set('state', state);
    const url = new URL(`${this.config.apiUrl}/auth/v1/authorize`);
    url.search = new URLSearchParams({ provider, redirect_to: target.href, code_challenge: challenge, code_challenge_method: 's256' });
    const result = await identity.launchWebAuthFlow({ url: url.href, interactive: true });
    if (Date.now() - started > 10 * 60000) throw new Error('Sign-in expired. Please retry.');
    const code = callbackValue(result, redirect, state, 'code');
    return this.normalize(await this.raw('/auth/v1/token?grant_type=pkce', { auth_code: code, code_verifier: verifier }, null, true));
  }
  async captcha(identity) {
    const started = Date.now(), state = nonce();
    const redirect = identity.getRedirectURL('captcha-callback');
    const url = new URL('/auth/extension-challenge.html', this.config.webUrl);
    url.searchParams.set('returnTo', redirect); url.hash = new URLSearchParams({ state }).toString();
    const result = await identity.launchWebAuthFlow({ url: url.href, interactive: true });
    if (Date.now() - started > 5 * 60000) throw new Error('Verification expired. Please retry.');
    return callbackValue(result, redirect, state, 'token');
  }
}
