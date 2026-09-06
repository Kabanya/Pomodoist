import { type JsonMap, object, TelegramError, uuidPattern } from './commands.ts';
export type Button = { text: string; callback_data?: string; url?: string; web_app?: { url: string } };
export type Screen = { text: string; reply_markup: { inline_keyboard: Button[][] } };
const en = {
  inbox: 'Inbox', today: 'Today', upcoming: 'Upcoming', completed: 'Completed', focus: 'Focus', account: 'Account',
  add: 'Add task', edit: 'Edit title', note: 'Edit notes', date: 'Schedule (all-day)', done: 'Complete', undo: 'Restore',
  del: 'Delete', yes: 'Yes, delete', back: 'Back', refresh: 'Refresh', pause: 'Pause', resume: 'Resume', stop: 'Stop', finish: 'Finish interval',
  empty: 'No tasks in this view.', saved: 'Saved.', removed: 'Task deleted.', link: 'Connect existing account', linked: 'Connected to your Pomodoist account.',
  guest: 'Telegram guest. Connect your existing account to synchronize with the main app.', open: 'Open Mini App',
  help: 'Pomodoist in Telegram\n\nSend a message to add a task. Open a task from a list to edit, complete, schedule or delete it.\n\n/inbox /today /upcoming /completed\n/focus /pause /resume /stop /finish\n/account /help /cancel\n\nSchedule uses YYYY-MM-DD for an all-day date; clear removes the schedule. Edit and notes can be entered by replying to the bot prompt. Lists include your account’s tasks, not only tasks created in Telegram.',
  confirm: 'Delete this task and its subtasks?', newPrompt: 'Reply with the task title, or send /cancel.',
  editPrompt: 'Reply with the new task title, or send /cancel.', notePrompt: 'Reply with the notes (clear removes them), or send /cancel.',
  datePrompt: 'Reply with YYYY-MM-DD to set an all-day date (this replaces a timed schedule). Send clear to remove it, or /cancel.',
  noFocus: 'No active Focus. Open a task and press Focus to start a 25-minute interval.',
  focusNote: 'The timer continues when this chat is closed. Refresh for the current remaining time. Finish is available only after the interval has elapsed.',
  error: 'Could not perform this action. Refresh and try again.', changed: 'This task changed. Refresh its card before editing it.',
  expired: 'This control expired. Open a fresh task list or /focus.', notFound: 'Task not found. Refresh the list.',
  recurring: 'Use the main app to delete recurring occurrences or remove their recurrence. No task was changed.',
  tooLarge: 'This task has too many subtasks for one atomic action. Manage this hierarchy in the main app.',
  activeFocus: 'Stop the task’s active Focus before deleting it.', focusChanged: 'Focus changed. Open /focus for its current state.',
  notElapsed: 'The interval has not elapsed yet. Open /focus to check the remaining time.', invalid: 'Invalid input. Use the controls or /help.',
};
const ru: typeof en = {
  inbox: 'Входящие', today: 'Сегодня', upcoming: 'Предстоящие', completed: 'Выполненные', focus: 'Фокус', account: 'Аккаунт',
  add: 'Добавить задачу', edit: 'Изменить название', note: 'Изменить заметки', date: 'Дата без времени', done: 'Выполнить', undo: 'Восстановить',
  del: 'Удалить', yes: 'Да, удалить', back: 'Назад', refresh: 'Обновить', pause: 'Пауза', resume: 'Продолжить', stop: 'Остановить', finish: 'Завершить интервал',
  empty: 'В этом списке нет задач.', saved: 'Сохранено.', removed: 'Задача удалена.', link: 'Подключить существующий аккаунт', linked: 'Подключён ваш аккаунт Pomodoist.',
  guest: 'Гость Telegram. Подключите существующий аккаунт для синхронизации с основным приложением.', open: 'Открыть Mini App',
  help: 'Pomodoist в Telegram\n\nОтправьте сообщение, чтобы добавить задачу. Откройте задачу из списка, чтобы изменить, выполнить, запланировать или удалить её.\n\n/inbox /today /upcoming /completed\n/focus /pause /resume /stop /finish\n/account /help /cancel\n\nДата без времени: YYYY-MM-DD; clear снимает дату. Название и заметки можно вводить ответом на запрос бота. Здесь доступны задачи всего аккаунта, а не только созданные в Telegram.',
  confirm: 'Удалить эту задачу и её подзадачи?', newPrompt: 'Ответьте названием задачи или отправьте /cancel.',
  editPrompt: 'Ответьте новым названием задачи или отправьте /cancel.', notePrompt: 'Ответьте текстом заметок (clear удаляет их) или отправьте /cancel.',
  datePrompt: 'Ответьте датой YYYY-MM-DD без времени (она заменит дату со временем). clear снимает дату, /cancel возвращает в меню.',
  noFocus: 'Нет активного Фокуса. Откройте задачу и нажмите «Фокус», чтобы начать 25-минутный интервал.',
  focusNote: 'Таймер продолжается после закрытия чата. «Обновить» покажет остаток времени. Завершение доступно только после окончания интервала.',
  error: 'Не удалось выполнить действие. Обновите список и повторите попытку.', changed: 'Задача изменилась. Обновите карточку перед редактированием.',
  expired: 'Эта кнопка устарела. Откройте новый список задач или /focus.', notFound: 'Задача не найдена. Обновите список.',
  recurring: 'Удаляйте повторяющиеся задачи и снимайте повторение в основном приложении. Задачи не изменены.',
  tooLarge: 'У задачи слишком много подзадач для одной атомарной операции. Измените эту группу в основном приложении.',
  activeFocus: 'Перед удалением остановите активный Фокус этой задачи.', focusChanged: 'Состояние Фокуса изменилось. Откройте /focus.',
  notElapsed: 'Интервал ещё не закончился. Откройте /focus, чтобы проверить остаток времени.', invalid: 'Некорректный ввод. Используйте кнопки или /help.',
};
export function copy(language: unknown) { return String(language ?? '').toLowerCase().startsWith('ru') ? ru : en; }
export function navigation(t: typeof en): Button[][] {
  return [[{ text: t.inbox, callback_data: 'list:inbox:0' }, { text: t.today, callback_data: 'list:today:0' }],
    [{ text: t.upcoming, callback_data: 'list:upcoming:0' }, { text: t.completed, callback_data: 'list:completed:0' }],
    [{ text: t.focus, callback_data: 'focus' }, { text: t.account, callback_data: 'account' }],
    [{ text: t.add, callback_data: 'new' }]];
}
const actions = new Set(['view', 'done', 'undo', 'edit', 'note', 'date', 'del', 'yes', 'go', 'pause', 'resume', 'stop', 'finish']);
export function actionData(action: string, id: string, revision: number, now: Date) {
  if (!actions.has(action) || !uuidPattern.test(id) || !Number.isSafeInteger(revision) || revision < 0) throw new TelegramError('invalid_control');
  const value = `${action}:${id.replaceAll('-', '')}:${Math.floor(+now / 1000).toString(36)}:${revision.toString(36)}`;
  if (new TextEncoder().encode(value).length > 64) throw new TelegramError('invalid_control');
  return value;
}
export function readAction(value: string, now: Date) {
  const match = /^([a-z]+):([0-9a-f]{32}):([0-9a-z]{1,10}):([0-9a-z]{1,11})$/i.exec(value);
  if (!match || !actions.has(match[1])) throw new TelegramError('invalid_control');
  const issued = parseInt(match[3], 36), revision = parseInt(match[4], 36), h = match[2].toLowerCase();
  if (issued > +now / 1000 + 30 || +now / 1000 - issued > 900) throw new TelegramError('control_expired', 409);
  const id = `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
  if (!uuidPattern.test(id) || !Number.isSafeInteger(revision)) throw new TelegramError('invalid_control');
  return { action: match[1], id, revision, issued };
}
const shorten = (value: unknown, length: number) => [...String(value ?? '')].slice(0, length).join('');
export function listScreen(snapshot: JsonMap, t: typeof en, now: Date): Screen {
  const view = String(snapshot.view ?? 'inbox') as 'inbox' | 'today' | 'upcoming' | 'completed';
  const tasks = Array.isArray(snapshot.tasks) ? snapshot.tasks as JsonMap[] : [];
  const page = Number(snapshot.page ?? 0), pages = Number(snapshot.pages ?? 1);
  const rows: Button[][] = tasks.filter(task => uuidPattern.test(String(task.id))).map(task => [{
    text: `${task.day ? `${task.day} · ` : ''}${shorten(task.content, 45)}`,
    callback_data: actionData('view', String(task.id), Number(task.revision ?? 0), now),
  }]);
  const paging: Button[] = [];
  if (page > 0) paging.push({ text: '←', callback_data: `list:${view}:${page - 1}` });
  paging.push({ text: t.refresh, callback_data: `list:${view}:${page}` });
  if (page + 1 < pages) paging.push({ text: '→', callback_data: `list:${view}:${page + 1}` });
  return { text: `${t[view] ?? t.inbox} · ${snapshot.timeZone ?? 'UTC'}\n${page + 1}/${pages} · ${snapshot.total ?? 0}${tasks.length ? '' : `\n\n${t.empty}`}`,
    reply_markup: { inline_keyboard: [...rows, paging, ...navigation(t)] } };
}
export function taskScreen(task: JsonMap | null, t: typeof en, now: Date, confirm = false): Screen {
  if (!task) throw new TelegramError('task_not_found', 404);
  const button = (action: string, title: string): Button => ({ text: title, callback_data: actionData(action, String(task.id), Number(task.revision ?? 0), now) });
  const rows = confirm ? [[button('yes', t.yes), button('view', t.back)]] : [
    [task.status === 'completed' ? button('undo', t.undo) : button('done', t.done), button('edit', t.edit)],
    [button('date', t.date), button('note', t.note)],
    [...(task.status === 'completed' ? [] : [button('go', t.focus)]), button('del', t.del)],
  ];
  return { text: `${confirm ? `${t.confirm}\n\n` : ''}${shorten(task.content, 2000)}${task.day ? `\n${task.day}` : ''}${task.description ? `\n\n${shorten(task.description, 1000)}` : ''}`,
    reply_markup: { inline_keyboard: [...rows, ...navigation(t)] } };
}
export function focusScreen(snapshot: JsonMap, t: typeof en, now: Date): Screen {
  const focus = object(snapshot.focus), run = object(focus?.run), interval = object(focus?.interval);
  if (!run || !interval) return { text: t.noFocus, reply_markup: { inline_keyboard: navigation(t) } };
  const paused = interval.status === 'paused';
  const start = new Date(interval.startedAt as string).getTime();
  const effective = paused ? new Date(interval.pausedAt as string).getTime() : +now;
  const elapsed = Math.max(0, Math.floor((effective - start) / 1000) - Number(interval.pausedTotalSeconds ?? 0));
  const seconds = Math.max(0, Number(interval.plannedSeconds ?? 1500) - elapsed);
  const clock = `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`;
  const b = (action: string, title: string) => ({ text: title, callback_data: actionData(action, String(run.id), 0, now) });
  return { text: `${t.focus} · ${clock}${paused ? ` · ${t.pause}` : ''}\n\n${t.focusNote}`,
    reply_markup: { inline_keyboard: [[b(paused ? 'resume' : 'pause', paused ? t.resume : t.pause), b('stop', t.stop)],
      ...(seconds === 0 ? [[b('finish', t.finish)]] : []), [{ text: t.refresh, callback_data: 'focus' }], ...navigation(t)] } };
}
export function errorText(code: string, t: typeof en) {
  if (code === 'task_changed') return t.changed;
  if (code === 'control_expired' || code === 'invalid_prompt') return t.expired;
  if (code === 'task_not_found') return t.notFound;
  if (code === 'recurring_task_requires_app') return t.recurring;
  if (code === 'task_batch_too_large') return t.tooLarge;
  if (code === 'task_has_active_focus') return t.activeFocus;
  if (code.startsWith('focus_')) return code === 'focus_not_elapsed' ? t.notElapsed : t.focusChanged;
  return code.startsWith('invalid_') ? t.invalid : t.error;
}
