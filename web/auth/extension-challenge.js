// Hosted on the web app, not packaged in the extension. No password or account
// token crosses this page; only a short-lived CAPTCHA token and a random nonce.
export function parseChallenge(href) {
  const request = new URL(href), query = request.searchParams, fragment = new URLSearchParams(request.hash.slice(1));
  const state = fragment.get('state'), raw = query.get('returnTo');
  if ([...query.keys()].length !== 1 || query.getAll('returnTo').length !== 1 ||
      [...fragment.keys()].length !== 1 || fragment.getAll('state').length !== 1 ||
      !/^[A-Za-z0-9_-]{32,128}$/.test(state ?? '')) throw new Error('Invalid verification request.');
  const target = new URL(raw);
  if (target.href !== raw || target.protocol !== 'https:' || !/^[a-p]{32}\.chromiumapp\.org$/.test(target.hostname) ||
      target.pathname !== '/captcha-callback' || target.port || target.username || target.password || target.search || target.hash) {
    throw new Error('Invalid extension callback.');
  }
  return { target, state };
}
if (typeof document !== 'undefined') {
  const status = document.getElementById('status'), retry = document.getElementById('retry');
  let request, widgetId, completed = false;
  const failed = message => { status.textContent = message; retry.hidden = false; };
  const render = () => {
    retry.hidden = true;
    if (widgetId !== undefined) window.turnstile.remove(widgetId);
    status.textContent = 'Confirm you are human to continue signing in.';
    widgetId = window.turnstile.render('#widget', {
      sitekey: window.pomodoistRuntimeConfig.turnstileSiteKey,
      callback: token => {
        if (completed || typeof token !== 'string' || !token || token.length > 2048 || /[\u0000-\u001f\u007f-\u009f]/.test(token)) return;
        completed = true; const callback = new URL(request.target.href);
        callback.searchParams.set('state', request.state); callback.searchParams.set('token', token);
        status.textContent = 'Verified. Returning to Pomodoist…'; location.replace(callback.href);
      },
      'error-callback': () => failed('Verification failed. Please retry.'),
      'expired-callback': () => failed('Verification expired. Please retry.'),
    });
  };
  try {
    request = parseChallenge(location.href);
    if (!window.pomodoistRuntimeConfig?.turnstileSiteKey) throw new Error('Verification is not configured on this server.');
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.onload = () => { clearTimeout(timeout); try { render(); } catch { failed('Verification could not start. Please retry.'); } };
    script.onerror = () => { clearTimeout(timeout); failed('Verification could not load. Check your connection and retry.'); };
    const timeout = setTimeout(() => failed('Verification timed out. Please retry.'), 15000);
    retry.addEventListener('click', () => location.reload()); document.head.append(script);
  } catch (error) { status.textContent = `${error.message} Close this window and retry sign-in from the extension.`; }
}
