const copies = {
  "en": {
    "title": "Pomodoist security check",
    "loading": "Loading verification…",
    "prompt": "Confirm you are human to continue signing in.",
    "invalid": "This verification link is invalid. Close this window and retry sign-in from the extension.",
    "error": "Verification failed. Check your connection and retry.",
    "expired": "Verification expired. Please retry.",
    "returning": "Verified. Returning to Pomodoist…",
    "retry": "Retry",
    "back": "Return to Pomodoist"
  },
  "pt-BR": {
    "title": "Verificação de segurança do Pomodoist",
    "loading": "Carregando verificação…",
    "prompt": "Confirme que você é uma pessoa para continuar o login.",
    "invalid": "Este link de verificação é inválido. Volte ao Pomodoist e tente entrar novamente.",
    "error": "Não foi possível carregar a verificação. Verifique sua conexão e tente novamente.",
    "expired": "A verificação expirou. Tente novamente.",
    "returning": "Verificação concluída. Voltando ao Pomodoist…",
    "retry": "Tentar verificar novamente",
    "back": "Voltar ao Pomodoist"
  },
  "ja": {
    "title": "Pomodoistのセキュリティ確認",
    "loading": "認証を読み込み中…",
    "prompt": "ログインを続けるには、人間であることを確認してください。",
    "invalid": "この認証リンクは無効です。Pomodoistに戻り、もう一度ログインしてください。",
    "error": "認証を読み込めませんでした。接続を確認して再試行してください。",
    "expired": "認証の有効期限が切れました。再試行してください。",
    "returning": "認証が完了しました。Pomodoistに戻っています…",
    "retry": "認証を再試行",
    "back": "Pomodoistに戻る"
  },
  "ko": {
    "title": "Pomodoist 보안 확인",
    "loading": "인증을 불러오는 중…",
    "prompt": "로그인을 계속하려면 사람임을 확인하세요.",
    "invalid": "인증 링크가 올바르지 않습니다. Pomodoist로 돌아가 다시 로그인하세요.",
    "error": "인증을 불러오지 못했습니다. 연결을 확인하고 다시 시도하세요.",
    "expired": "인증이 만료되었습니다. 다시 시도하세요.",
    "returning": "인증이 완료되었습니다. Pomodoist로 돌아가는 중…",
    "retry": "인증 다시 시도",
    "back": "Pomodoist로 돌아가기"
  }
};
// Hosted on the web app, not packaged in the extension. No password or account
// token crosses this page; only a short-lived CAPTCHA token and a random nonce.
export function parseChallenge(href) {
  const request = new URL(href), query = request.searchParams, fragment = new URLSearchParams(request.hash.slice(1));
  const state = fragment.get('state'), raw = query.get('returnTo');
  if ([...query.keys()].some(key => !['returnTo', 'lang'].includes(key)) || query.getAll('returnTo').length !== 1 ||
      query.getAll('lang').length > 1 || (query.has('lang') && !Object.hasOwn(copies, query.get('lang'))) ||
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
  const requested = new URLSearchParams(location.search).get('lang');
  const languages = [requested, ...(navigator.languages || [navigator.language])].map(value => String(value || '').toLowerCase().split(/[-_]/)[0]).map(value => value === 'pt' ? 'pt-BR' : value);
  const language = languages.find(value => Object.hasOwn(copies, value)) || 'en';
  const copy = copies[language];
  document.documentElement.lang = language;
  document.title = copy.title;
  document.querySelector('h1').textContent = copy.title;
  document.getElementById('status').textContent = copy.loading;
  document.getElementById('retry').textContent = copy.retry;
  const status = document.getElementById('status'), retry = document.getElementById('retry');
  let request, widgetId, completed = false;
  const failed = message => { status.textContent = message; retry.hidden = false; };
  const render = () => {
    retry.hidden = true;
    if (widgetId !== undefined) window.turnstile.remove(widgetId);
    status.textContent = copy.prompt;
    widgetId = window.turnstile.render('#widget', {
      sitekey: window.pomodoistRuntimeConfig.turnstileSiteKey, language,
      callback: token => {
        if (completed || typeof token !== 'string' || !token || token.length > 2048 || /[\u0000-\u001f\u007f-\u009f]/.test(token)) return;
        completed = true; const callback = new URL(request.target.href);
        callback.searchParams.set('state', request.state); callback.searchParams.set('token', token);
        status.textContent = copy.returning; location.replace(callback.href);
      },
      'error-callback': () => failed(copy.error),
      'expired-callback': () => failed(copy.expired),
    });
  };
  try {
    request = parseChallenge(location.href);
    if (!window.pomodoistRuntimeConfig?.turnstileSiteKey) throw new Error('Verification is not configured on this server.');
    const script = document.createElement('script');
    script.src = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit';
    script.onload = () => { clearTimeout(timeout); try { render(); } catch { failed(copy.error); } };
    script.onerror = () => { clearTimeout(timeout); failed(copy.error); };
    const timeout = setTimeout(() => failed(copy.expired), 15000);
    retry.addEventListener('click', () => location.reload()); document.head.append(script);
  } catch (error) { status.textContent = request ? copy.error : copy.invalid; }
}
