// In-memory Pomodoist backend used by the Mini App browser preview and regression.
// It reuses the deployed commands module, so previews and tests exercise real
// task/focus semantics instead of a hand-written stub.
import { taskPage, taskOperations, validateCommand, TelegramError } from '../server/supabase/functions/pomodoist-telegram/commands.ts';
import { telegramEntityId } from '../apps/telegram-mini-app/core.js';

export function createTelegramFixture() {
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: 'Europe/Moscow' }).format(new Date());
  const id = n => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
  const emptyModel = () => ({ tasks: new Map(), projects: new Map(), focusRuns: new Map(), focusIntervals: new Map(), entities: [] });
  const model = emptyModel(), guestModel = emptyModel();
  model.projects.set('release', { name: 'Pomodoist' });
  let revision = 0, focus = null, linked = false, guestMode = false;
  const receipts = new Set();
  // Task dates need a stable reference day, but Focus timing must advance in
  // real time or a pause would collapse into the start instant.
  const now = () => new Date();
  function put(task) {
    model.tasks.set(task.id, task);
    model.entities = model.entities.filter(entry => entry.entityId !== task.id);
    model.entities.push({ entityType: 'task', entityId: task.id, serverRevision: ++revision, data: task });
  }
  for (const [n, content] of ['Продумать Telegram Mini App', 'Проверить сценарий фокуса', 'Подготовить заметки к релизу', 'Разобрать входящие', 'Записать идеи', 'Обновить документацию', 'Проверить мобильную версию', 'Ответить на вопросы'].entries()) {
    put({ id: id(n + 1), content, status: 'open', projectId: 'inbox', priority: n === 0 ? 1 : 4, orderKey: String(n), dueJson: n === 0 ? JSON.stringify({ type: 'allDay', date: day }) : null });
  }
  put({ id: id(20), content: 'Задача проекта', status: 'open', projectId: 'release', priority: 2, dueJson: JSON.stringify({ type: 'allDay', date: '2099-12-31' }) });
  function snapshot(body) {
    const source = guestMode ? guestModel : model;
    return { account: { linked }, inbox: [...source.tasks.values()].filter(task => !task.isDeleted && task.projectId === 'inbox' && task.status !== 'completed'),
      focus: guestMode ? null : focus, generatedAt: now().toISOString(), ...taskPage(source, now(), body) };
  }
  function command(input, body) {
    validateCommand(input);
    if (!receipts.has(input.id)) {
      const operations = taskOperations(model, input, now());
      if (input.type === 'task.create') put({ id: telegramEntityId(input.id), content: input.content, status: 'open', projectId: 'inbox', priority: 4, dueJson: null });
      else if (operations) for (const operation of operations.filter(item => item.entityType === 'task')) put({ ...model.tasks.get(operation.entityId), ...operation.payload });
      else if (input.type === 'focus.start') {
        focus = { run: { id: telegramEntityId(input.id), taskId: input.taskId ?? null, status: 'active' },
          interval: { id: telegramEntityId(input.id, 2n), runId: telegramEntityId(input.id), status: 'running', plannedSeconds: 1500, startedAt: now().toISOString(), pausedAt: null, pausedTotalSeconds: 0 } };
      } else if (input.type === 'focus.pause') { focus.run.status = 'paused'; focus.interval.status = 'paused'; focus.interval.pausedAt = now().toISOString(); }
      else if (input.type === 'focus.resume') {
        // Mirror focusUpdateOps: the paused stretch adds to pausedTotalSeconds.
        const pausedAt = Date.parse(focus.interval.pausedAt);
        focus.interval.pausedTotalSeconds = Number(focus.interval.pausedTotalSeconds || 0) +
          (Number.isFinite(pausedAt) ? Math.max(0, Math.floor((now().getTime() - pausedAt) / 1000)) : 0);
        focus.run.status = 'active'; focus.interval.status = 'running'; focus.interval.pausedAt = null;
      }
      else if (input.type === 'focus.stop' || input.type === 'focus.complete') focus = null;
      model.focusRuns.clear(); model.focusIntervals.clear();
      if (focus) { model.focusRuns.set(focus.run.id, focus.run); model.focusIntervals.set(focus.interval.id, focus.interval); }
      receipts.add(input.id);
    }
    return snapshot({ ...body, taskId: input.taskId });
  }
  function respond(body) {
    try {
      if (body.action === 'begin_link') return { ok: true, data: { url: 'https://mini.example/telegram-account-link?token=fixture' } };
      if (body.action === 'unlink_account') { linked = false; guestMode = true; return { ok: true, data: snapshot(body) }; }
      if (body.action === 'command') return { ok: true, data: command(body.command, body) };
      return { ok: true, data: snapshot(body) };
    } catch (error) {
      if (!(error instanceof TelegramError)) throw error;
      return { status: error.status, ok: false, code: error.code };
    }
  }
  return { respond, model, snapshot, put,
    get focus() { return focus; },
    set linked(value) { linked = value; }, get linked() { return linked; },
    set guestMode(value) { guestMode = value; }, get guestMode() { return guestMode; } };
}

// Browser-side Telegram stub. The Mini App only needs initData to be a non-empty
// string to enter its Telegram branch; screenshots and previews never verify it.
export const telegramStubSource = `(() => {
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
})();`;
