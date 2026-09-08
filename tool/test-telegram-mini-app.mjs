// Run with Node 22+ and Playwright available (NODE_PATH may point to the bundled runtime).
import assert from 'node:assert/strict';
import { readFile, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { taskPage, taskOperations, validateCommand, TelegramError } from '../server/supabase/functions/pomodoist-telegram/commands.ts';
import { telegramEntityId } from '../telegram-mini-app/core.js';
const { chromium } = createRequire(import.meta.url)('playwright');
const browser = await chromium.launch({ channel: 'chrome', headless: true });
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'ru-RU', timezoneId: 'Europe/Moscow' });
const page = await context.newPage();
const errors = [];
page.on('pageerror', error => errors.push(error.message));
page.setDefaultTimeout(8000);
const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Moscow' }).format(new Date());
const future = '2099-12-31';
const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const model = { tasks: new Map(), projects: new Map([['release', { name: 'Pomodoist' }]]), focusRuns: new Map(), focusIntervals: new Map(), entities: [] };
const guestModel = { tasks: new Map(), projects: new Map(), focusRuns: new Map(), focusIntervals: new Map(), entities: [] };
let revision = 0, focus = null, linked = false, guestMode = false, unavailable = false, unlinkUnavailable = false, holdCommand, releaseCommand, dropReply;
let snapshotRequests = 0, unlinkRequests = 0;
const commands = [], receipts = new Set();
function put(task) {
  model.tasks.set(task.id, task);
  model.entities = model.entities.filter(e => e.entityId !== task.id);
  model.entities.push({ entityType: 'task', entityId: task.id, serverRevision: ++revision, data: task });
}
for (const [n, content] of ['Продумать Telegram Mini App', 'Проверить сценарий фокуса', 'Подготовить заметки к релизу', 'Разобрать входящие', 'Записать идеи', 'Обновить документацию', 'Проверить мобильную версию', 'Ответить на вопросы'].entries()) {
  put({ id: id(n + 1), content, status: 'open', projectId: 'inbox', priority: n === 0 ? 1 : 4, orderKey: String(n), dueJson: n === 0 ? JSON.stringify({ type: 'allDay', date: day }) : null });
}
put({ id: id(20), content: 'Задача проекта', status: 'open', projectId: 'release', priority: 2, dueJson: JSON.stringify({ type: 'allDay', date: future }) });
function snapshot(body) {
  const source = guestMode ? guestModel : model;
  return { account: { linked }, inbox: [...source.tasks.values()].filter(t => !t.isDeleted && t.projectId === 'inbox' && t.status !== 'completed'), focus: guestMode ? null : focus, generatedAt: new Date().toISOString(), ...taskPage(source, new Date(), body) };
}
await context.addInitScript(() => {
  const handlers = {};
  const control = () => ({ onClick(fn) { this.click = fn; }, show() {}, hide() {} });
  window.testTelegram = { handlers, links: [], haptics: [], colors: [], confirms: [], confirmResult: true };
  window.Telegram = { WebApp: { initData: 'signed-fixture', initDataUnsafe: { user: { id: 42, language_code: 'ru' } }, colorScheme: 'light',
    ready() {}, expand() {}, onEvent(name, fn) { handlers[name] = fn; }, isVersionAtLeast() { return true; },
    setHeaderColor(value) { window.testTelegram.colors.push(value); }, setBackgroundColor() {}, setBottomBarColor() {},
    BackButton: control(), SettingsButton: control(), MainButton: control(), SecondaryButton: control(),
    HapticFeedback: { impactOccurred(value) { window.testTelegram.haptics.push(value); }, notificationOccurred(value) { window.testTelegram.haptics.push(value); } },
    showConfirm(message, callback) { window.testTelegram.confirms.push(message); callback(window.testTelegram.confirmResult); },
    openLink(url) { window.testTelegram.links.push(url); },
  } };
});
await page.route('**/*', async route => {
  const url = new URL(route.request().url());
  if (url.hostname === 'telegram.org') return route.fulfill({ body: '', contentType: 'text/javascript' });
  if (url.pathname === '/config.js') return route.fulfill({ contentType: 'text/javascript', body: 'window.pomodoistRuntimeConfig = {supabaseUrl: "https://mini.example", supabaseAnonKey:"fixture"};' });
  if (url.pathname.startsWith('/telegram/')) {
    const file = url.pathname.split('/').at(-1) || 'index.html';
    return route.fulfill({ body: await readFile(new URL(`../telegram-mini-app/${file}`, import.meta.url)), contentType: file.endsWith('.js') ? 'text/javascript' : file.endsWith('.css') ? 'text/css' : 'text/html' });
  }
  if (!url.pathname.endsWith('/pomodoist-telegram')) return route.fulfill({ status: 404, body: '' });
  const body = route.request().postDataJSON();
  if (unavailable) return route.fulfill({ status: 503, json: { ok: false, code: 'request_failed' } });
  let data;
  try {
    if (body.action === 'begin_link') data = { url: 'https://mini.example/telegram-account-link?token=fixture' };
    else if (body.action === 'unlink_account') {
      unlinkRequests++;
      if (unlinkUnavailable) return route.fulfill({ status: 503, json: { ok: false, code: 'request_failed' } });
      linked = false; guestMode = true; data = snapshot(body);
    }
    else if (body.action === 'command') {
      const command = body.command;
      commands.push(command);
      validateCommand(command);
      if (!receipts.has(command.id)) {
        const operations = taskOperations(model, command, new Date());
        if (command.type === 'task.create') put({ id: telegramEntityId(command.id), content: command.content, status: 'open', projectId: 'inbox', priority: 4, dueJson: null });
        else if (operations) for (const op of operations.filter(op => op.entityType === 'task')) put({ ...model.tasks.get(op.entityId), ...op.payload });
        else if (command.type === 'focus.start') {
          focus = { run: { id: telegramEntityId(command.id), taskId: command.taskId ?? null, status: 'active' }, interval: { id: telegramEntityId(command.id, 2n), runId: telegramEntityId(command.id), status: 'running', plannedSeconds: 1500, startedAt: new Date().toISOString(), pausedAt: null, pausedTotalSeconds: 0 } };
        } else if (command.type === 'focus.pause') {
          focus.run.status = 'paused'; focus.interval.status = 'paused'; focus.interval.pausedAt = new Date().toISOString();
        } else if (command.type === 'focus.resume') {
          focus.run.status = 'active'; focus.interval.status = 'running'; focus.interval.pausedAt = null;
        } else if (command.type === 'focus.stop' || command.type === 'focus.complete') focus = null;
        model.focusRuns.clear(); model.focusIntervals.clear();
        if (focus) { model.focusRuns.set(focus.run.id, focus.run); model.focusIntervals.set(focus.interval.id, focus.interval); }
        receipts.add(command.id);
      }
      data = snapshot({ ...body, taskId: command.taskId });
      if (dropReply === command.type) { dropReply = null; return route.abort('failed'); }
      if (holdCommand === command.type) { holdCommand = null; await new Promise(resolve => { releaseCommand = resolve; }); }
    } else { snapshotRequests++; data = snapshot(body); }
    await route.fulfill({ json: { ok: true, data } });
  } catch (error) {
    if (!(error instanceof TelegramError)) throw error;
    await route.fulfill({ status: error.status, json: { ok: false, code: error.code } });
  }
});
const nav = view => page.locator(`.navigation [data-view="${view}"]`).click();
const waitView = async name => { await page.locator('#inbox-title').filter({ hasText: name }).waitFor(); await page.waitForFunction(() => !document.querySelector('#empty').textContent.includes('Загрузка')); };
const task = n => page.locator(`[data-task="${id(n)}"]`);
const closeTask = () => page.locator('#close-task').click();
const synced = () => page.waitForFunction(() => !localStorage.getItem('pomodoist.telegram.pending.v1'));
const output = process.env.TELEGRAM_SCREENSHOT_DIR;
try {
  await page.goto('https://mini.example/telegram/');
  await page.locator('#app:not([hidden])').waitFor();
  assert.deepEqual(await page.locator('.navigation [data-view]').evaluateAll(items => items.map(item => item.dataset.view)), ['inbox', 'today', 'upcoming', 'focus']);
  assert.equal(await page.locator('#sign-out').getAttribute('hidden'), '');
  assert.equal(await page.locator('.task').count(), 6);
  const initialSnapshots = snapshotRequests;
  await page.waitForTimeout(5500);
  assert.equal(snapshotRequests, initialSnapshots);
  if (output) {
    await mkdir(output, { recursive: true });
    for (const theme of ['light', 'dark']) {
      await page.evaluate(theme => { window.Telegram.WebApp.colorScheme = theme; window.testTelegram.handlers.themeChanged(); }, theme);
      await page.screenshot({ path: `${output}/inbox-${theme}.png`, fullPage: true });
    }
    await page.evaluate(() => { window.Telegram.WebApp.colorScheme = 'light'; window.testTelegram.handlers.themeChanged(); });
  }
  await page.locator('#next-page').click();
  await page.waitForFunction(() => document.querySelector('#page-number').textContent === '2 / 2');
  await page.locator('#task-list:not([hidden])').waitFor();
  assert.equal(await page.locator('.task').count(), 2);
  await nav('upcoming'); await waitView('Предстоящее');
  assert.equal(await page.locator('.task-title').textContent(), 'Задача проекта');
  await nav('today'); await waitView('Сегодня');
  await task(1).click(); await page.locator('#edit-title:enabled').waitFor();
  await page.locator('#edit-title').fill('Улучшить Telegram Mini App');
  await page.locator('#edit-note').fill('Карточка задачи, расписание и приоритет');
  await page.locator('#edit-priority').selectOption('2');
  await page.locator('#edit-date').fill(future);
  await page.locator('#save-task').click();
  await page.locator('#task-dialog').waitFor({ state: 'hidden' });
  await synced();
  assert.equal(model.tasks.get(id(1)).description, 'Карточка задачи, расписание и приоритет');
  assert.equal(model.tasks.get(id(1)).priority, 2);
  assert.equal(await page.locator('.task').count(), 0);
  await nav('upcoming'); await waitView('Предстоящее');
  assert.equal(await page.locator('.task').count(), 2);
  await page.locator(`[data-complete="${id(1)}"]`).click(); await synced();
  assert.equal(await task(1).count(), 0);
  await page.locator('#undo-button').click(); await synced();
  assert.equal(await task(1).count(), 1);
  holdCommand = 'task.complete';
  await page.locator(`[data-complete="${id(1)}"]`).click();
  await page.waitForFunction(() => !!localStorage.getItem('pomodoist.telegram.pending.v1'));
  await nav('today'); await waitView('Сегодня');
  releaseCommand(); await synced();
  assert.equal(await page.locator('#inbox-title').textContent(), 'Сегодня');
  await nav('inbox'); await waitView('Входящие');
  await task(2).click(); await page.locator('#edit-title:enabled').waitFor();
  await page.locator('#edit-note').fill('Черновик сохранён');
  await closeTask();
  await task(2).click(); await page.locator('#edit-title:enabled').waitFor();
  assert.equal(await page.locator('#edit-note').inputValue(), 'Черновик сохранён');
  put({ ...model.tasks.get(id(2)), content: 'Изменено на другом устройстве' });
  await page.locator('#save-task').click();
  await page.locator('#detail-error').filter({ hasText: 'изменилась' }).waitFor();
  assert.equal(await page.locator('#edit-note').inputValue(), 'Черновик сохранён');
  await page.locator('#refresh-task').click();
  await page.waitForFunction(() => document.querySelector('#edit-title').value === 'Изменено на другом устройстве');
  await page.locator('#save-task').click(); await page.locator('#task-dialog').waitFor({ state: 'hidden' });
  assert.equal(model.tasks.get(id(2)).content, 'Изменено на другом устройстве');
  assert.equal(model.tasks.get(id(2)).description, 'Черновик сохранён');
  await task(2).click(); await page.locator('#edit-title:enabled').waitFor();
  await page.locator('#start-focus').click(); await waitView('Фокус'); await synced();
  await page.locator('#focus-toggle').click(); await synced();
  assert.equal(focus.interval.status, 'paused');
  assert.ok(await page.evaluate(() => window.testTelegram.haptics.length > 0));
  await page.reload(); await page.locator('#app:not([hidden])').waitFor();
  assert.equal(await page.locator('#focus-toggle').textContent(), 'Продолжить');
  await page.locator('#focus-toggle').click(); await synced();
  assert.equal(focus.interval.status, 'running');
  await page.locator('#focus-stop').click(); await synced();
  assert.equal(focus, null);
  await nav('focus'); await page.locator('#focus-empty:not([hidden])').waitFor();
  const taskCount = model.tasks.size;
  dropReply = 'focus.start';
  await page.locator('#focus-start').click();
  await page.locator('#toast:not([hidden])').waitFor();
  assert.equal(focus.run.taskId, null);
  const standaloneRunId = focus.run.id;
  await page.reload(); await page.locator('#app:not([hidden])').waitFor(); await synced();
  assert.equal(focus.run.id, standaloneRunId);
  assert.equal(focus.run.taskId, null);
  assert.equal(model.tasks.size, taskCount);
  assert.equal(await page.locator('#focus-task').textContent(), 'Фокус');
  await page.locator('#focus-toggle').click(); await synced();
  assert.equal(focus.interval.status, 'paused');
  await page.reload(); await page.locator('#app:not([hidden])').waitFor();
  assert.equal(await page.locator('#focus-toggle').textContent(), 'Продолжить');
  await page.locator('#focus-toggle').click(); await synced();
  assert.equal(focus.interval.status, 'running');
  await page.locator('#focus-stop').click(); await synced();
  assert.equal(focus, null);
  await task(3).click(); await page.locator('#edit-title:enabled').waitFor();
  await page.locator('#delete-task').click();
  assert.equal(model.tasks.get(id(3)).isDeleted, undefined);
  await page.locator('#cancel-delete').click();
  assert.equal(model.tasks.get(id(3)).isDeleted, undefined);
  await page.locator('#delete-task').click(); await page.locator('#confirm-delete').click();
  await page.locator('#task-dialog').waitFor({ state: 'hidden' }); await synced();
  assert.equal(model.tasks.get(id(3)).isDeleted, true);
  unavailable = true;
  await page.locator('#task-input').fill('Без сети'); await page.locator('#add-button').click();
  await page.locator('#sync-status').filter({ hasText: 'Ожидаем' }).waitFor();
  const pending = JSON.parse(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.pending.v1')));
  await page.reload(); await page.locator('#error:not([hidden])').waitFor();
  unavailable = false;
  await page.locator('#retry-button').click(); await page.locator('#app:not([hidden])').waitFor(); await synced();
  assert.equal([...model.tasks.values()].filter(t => t.content === 'Без сети').length, 1);
  assert.ok(receipts.has(pending[0].id));
  dropReply = 'task.create';
  await page.locator('#task-input').fill('Ответ потерян после сохранения'); await page.locator('#add-button').click();
  await page.locator('#toast:not([hidden])').waitFor();
  assert.ok(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.pending.v1')));
  await page.reload(); await page.locator('#app:not([hidden])').waitFor(); await synced();
  assert.equal([...model.tasks.values()].filter(t => t.content === 'Ответ потерян после сохранения').length, 1);
  await page.locator('#account-button').click(); await page.locator('#link-account').click();
  await page.waitForFunction(() => window.testTelegram.links.length > 0);
  assert.match(await page.evaluate(() => window.testTelegram.links.at(-1)), /telegram-account-link/);
  linked = true;
  await page.locator('#close-settings').click(); await page.locator('#refresh-button').click();
  await page.waitForFunction(() => document.querySelector('#link-account').hidden);
  assert.equal(await page.locator('#sign-out').getAttribute('hidden'), null);
  for (const theme of ['light', 'dark']) {
    await page.evaluate(theme => { window.Telegram.WebApp.colorScheme = theme; window.testTelegram.handlers.themeChanged(); }, theme);
    assert.equal(await page.locator('html').getAttribute('data-theme'), theme);
    await nav('focus'); await page.locator('#focus-empty:not([hidden])').waitFor();
    for (const width of [320, 390]) {
      await page.setViewportSize({ width, height: 844 });
      assert.equal(await page.locator('#focus-start').isVisible(), true);
      assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    }
    if (output) await page.screenshot({ path: `${output}/focus-ready-${theme}.png`, fullPage: true });
    await nav('inbox'); await waitView('Входящие');
    if (output) await page.screenshot({ path: `${output}/mini-app-${theme}.png`, fullPage: true });
    await task(2).click(); await page.locator('#edit-title:enabled').waitFor();
    assert.ok(await page.locator('#task-dialog').evaluate(el => el.scrollWidth <= el.clientWidth));
    if (output) await page.screenshot({ path: `${output}/task-${theme}.png` });
    await page.evaluate(() => window.Telegram.WebApp.BackButton.click());
    await page.locator('#task-dialog').waitFor({ state: 'hidden' });
  }
  await page.evaluate(() => {
    localStorage.setItem('pomodoist.telegram.draft.v1', 'Сохранить черновик');
    localStorage.setItem('pomodoist.telegram.task-draft.v1.fixture', 'detail');
    window.testTelegram.confirmResult = false;
  });
  await page.locator('#account-button').click();
  await page.locator('#sign-out').click();
  assert.equal(linked, true);
  assert.equal(unlinkRequests, 0);
  assert.equal(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.draft.v1')), 'Сохранить черновик');
  await page.evaluate(() => { window.testTelegram.confirmResult = true; });
  unlinkUnavailable = true;
  await page.locator('#sign-out').click();
  await page.locator('#account-error:not([hidden])').waitFor();
  assert.equal(linked, true);
  assert.equal(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.task-draft.v1.fixture')), 'detail');
  await page.locator('#close-settings').click();
  unavailable = true;
  await page.locator('#task-input').fill('Discard on logout'); await page.locator('#add-button').click();
  await page.locator('#sync-status').filter({ hasText: 'Ожидаем' }).waitFor();
  unavailable = false;
  await page.evaluate(() => localStorage.setItem('pomodoist.telegram.draft.v1', 'Удалить черновик'));
  await page.locator('#account-button').click();
  await page.locator('#sign-out:enabled').waitFor();
  unlinkUnavailable = false;
  await page.locator('#sign-out').click();
  await page.locator('#settings-dialog').waitFor({ state: 'hidden' });
  assert.equal(linked, false);
  assert.equal(await page.locator('.task').count(), 0);
  assert.equal(await page.locator('#inbox-title').textContent(), 'Входящие');
  assert.equal(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.draft.v1')), null);
  assert.equal(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.pending.v1')), null);
  assert.equal(await page.evaluate(() => localStorage.getItem('pomodoist.telegram.task-draft.v1.fixture')), null);
  assert.deepEqual(errors, []);
  console.log('Mini App browser checks passed: task lifecycle, four views, drafts, conflicts, focus, replay, linking, logout, polling, themes, mobile layout.');
} finally { await browser.close(); }
