import { pathToFileURL } from 'node:url';

export function telegramConfiguration(env) {
  const token = env.POMODOIST_TELEGRAM_BOT_TOKEN ?? '';
  const secret = env.POMODOIST_TELEGRAM_WEBHOOK_SECRET ?? '';
  if (!/^\d+:[A-Za-z0-9_-]+$/.test(token)) throw new Error('POMODOIST_TELEGRAM_BOT_TOKEN is required.');
  if (!/^[A-Za-z0-9_-]{32,256}$/.test(secret)) throw new Error('Use a random 32–256 character webhook secret.');
  const base = env.POMODOIST_TELEGRAM_WEBHOOK_URL || `${env.SUPABASE_PUBLIC_URL || env.SUPABASE_URL || ''}/functions/v1/pomodoist-telegram/webhook`;
  const webhook = new URL(base), web = new URL('/telegram/', env.POMODOIST_WEB_URL || env.SITE_URL);
  for (const url of [webhook, web]) {
    if (url.protocol !== 'https:' || url.username || url.password || url.hash || url.search || ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
      throw new Error('Public HTTPS URLs without credentials, query or fragments are required.');
    }
  }
  if (!webhook.pathname.endsWith('/pomodoist-telegram/webhook')) throw new Error('Webhook URL must end in /pomodoist-telegram/webhook.');
  const timeZone = env.POMODOIST_TELEGRAM_TIME_ZONE || 'UTC';
  new Intl.DateTimeFormat('en', { timeZone }).format();
  return { token, secret, webhook: webhook.href, miniApp: web.href };
}
const commands = {
  en: [ ['start', 'Open Pomodoist'], ['inbox', 'Inbox tasks'], ['today', 'Today and overdue'], ['upcoming', 'Upcoming tasks'],
    ['completed', 'Completed tasks'], ['add', 'Create a task'], ['focus', 'Show Focus timer'], ['pause', 'Pause Focus'],
    ['resume', 'Resume Focus'], ['stop', 'Stop Focus'], ['finish', 'Finish elapsed interval'], ['account', 'Connect your account'], ['help', 'Show help'], ['cancel', 'Return to the menu'] ],
  ru: [ ['start', 'Открыть Pomodoist'], ['inbox', 'Входящие задачи'], ['today', 'Сегодня и просроченные'], ['upcoming', 'Предстоящие задачи'],
    ['completed', 'Выполненные задачи'], ['add', 'Создать задачу'], ['focus', 'Таймер Фокуса'], ['pause', 'Пауза Фокуса'],
    ['resume', 'Продолжить Фокус'], ['stop', 'Остановить Фокус'], ['finish', 'Завершить истёкший интервал'], ['account', 'Подключить аккаунт'], ['help', 'Справка'], ['cancel', 'Вернуться в меню'] ],
};
export async function configureTelegramBot(env, fetcher = fetch) {
  const config = telegramConfiguration(env);
  const call = async (method, body) => {
    let response;
    try {
      response = await fetcher(`https://api.telegram.org/bot${config.token}/${method}`, { method: 'POST',
        headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(10000) });
    } catch { throw new Error(`Telegram ${method} request failed. Credentials were not logged.`); }
    const result = await response.json().catch(() => null);
    if (!response.ok || result?.ok !== true) throw new Error(`Telegram ${method} failed. Check credentials and deployment.`);
    return result.result;
  };
  if (env.POMODOIST_TELEGRAM_BOT_USERNAME) {
    const bot = await call('getMe', {});
    if (bot?.username !== env.POMODOIST_TELEGRAM_BOT_USERNAME.replace(/^@/, '')) {
      throw new Error('Bot token does not match POMODOIST_TELEGRAM_BOT_USERNAME. No settings changed.');
    }
  }
  for (const language of ['en', 'ru']) await call('setMyCommands', { ...(language === 'ru' ? { language_code: 'ru' } : {}),
    commands: commands[language].map(([command, description]) => ({ command, description })) });
  await call('setChatMenuButton', { menu_button: { type: 'web_app', text: 'Pomodoist', web_app: { url: config.miniApp } } });
  await call('setWebhook', { url: config.webhook, secret_token: config.secret,
    allowed_updates: ['message', 'callback_query'], drop_pending_updates: false, max_connections: 10 });
  const info = await call('getWebhookInfo', {});
  if (info?.url !== config.webhook) throw new Error('Webhook verification did not match the requested URL.');
  return { webhook: config.webhook };
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!process.argv.includes('--apply')) {
    console.error('No changes made. Run with --apply after deploying the function and its secrets.'); process.exitCode = 1;
  } else {
    try { await configureTelegramBot(process.env); console.log('Telegram commands, menu and webhook configured and verified.'); }
    catch (error) { console.error(error.message); process.exitCode = 1; }
  }
}
