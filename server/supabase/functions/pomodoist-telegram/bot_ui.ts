import { type JsonMap, object, TelegramError, uuidPattern } from './commands.ts';
export type Button = { text: string; callback_data?: string; url?: string; web_app?: { url: string } };
import { Message, shorten, oneLine, taskMeta, type Entity } from './bot_format.ts';
export type Screen = { text: string; entities?: Entity[]; reply_markup: { inline_keyboard: Button[][] } };
const en = {
  locale: 'en', cancel: 'Cancel', menu: 'Menu', task: 'Task', project: 'Project', priority: 'Priority {priority}',
  openState: 'Open', completeState: 'Completed', focused: 'In focus', current: 'In progress', future: 'Upcoming', overdue: 'Overdue',
  allDay: 'All-day', noDate: 'No date', deadline: 'Deadline', repeat: 'Repeat', tomorrow: 'Tomorrow', yesterday: 'Yesterday',
  inboxHint: 'Capture tasks before organizing them.', emptyToday: 'No tasks scheduled for this day', emptyUpcoming: 'No dated tasks',
  emptyCompleted: 'No completed tasks yet.', count: 'Tasks', page: 'Page', startFocus: 'Start focus',
  idle: 'No active session', work: 'Work', running: 'Running', paused: 'Paused', ready: 'Ready',
  choosePriority: 'Choose a priority',
  inbox: 'Inbox', today: 'Today', upcoming: 'Upcoming', completed: 'Completed tasks', focus: 'Focus', account: 'Account',
  add: 'Add task', edit: 'Edit title', note: 'Comment', date: 'Schedule', done: 'Mark complete', undo: 'Mark open',
  del: 'Delete', yes: 'Delete', back: 'Back', refresh: 'Refresh', pause: 'Pause', resume: 'Resume', stop: 'Stop', finish: 'Complete interval',
  empty: 'No tasks here', saved: 'Saved.', removed: 'Task deleted', link: 'Connect existing account', linked: 'Connected to your Pomodoist account.',
  guest: 'Telegram guest. Connect your existing account to synchronize with the main app.', open: 'Open Pomodoist',
  help: 'Send a message to add a task. Open a task from a list to edit, complete, schedule or delete it.\n\n/inbox /today /upcoming /completed\n/focus /pause /resume /stop /finish\n/account /help /cancel\n\nSchedule uses YYYY-MM-DD for an all-day date; clear removes the schedule. The title and comment can be entered by replying to the bot prompt. Lists include your account’s tasks, not only tasks created in Telegram.',
  confirm: 'Delete this task and its subtasks?', newPrompt: 'Reply with the task title, or send /cancel.',
  editPrompt: 'Reply with the new task title, or send /cancel.', notePrompt: 'Reply with the comment (clear removes it), or send /cancel.',
  datePrompt: 'Reply with YYYY-MM-DD to set an all-day date (this replaces a timed schedule). Send clear to remove it, or /cancel.',
  noFocus: 'Open a task and choose Start focus to begin a 25-minute work interval.',
  focusNote: 'The timer continues when this chat is closed. Refresh for the current remaining time. Finish is available only after the interval has elapsed.',
  error: 'Could not perform this action. Refresh and try again.', changed: 'This task changed. Refresh its card before editing it.',
  expired: 'This control expired. Open a fresh task list or /focus.', notFound: 'Task not found. Refresh the list.',
  recurring: 'Use the main app to delete recurring occurrences or remove their recurrence. No task was changed.',
  tooLarge: 'This task has too many sub-tasks to change together. Open Pomodoist to manage them. Nothing was changed.',
  activeFocus: 'Stop the task’s active Focus before deleting it.', focusChanged: 'Focus changed. Open /focus for its current state.',
  notElapsed: 'The interval has not elapsed yet. Open /focus to check the remaining time.', invalid: 'Invalid input. Use the controls or /help.',
};
const ru: typeof en = {
  locale: 'ru', cancel: 'Отмена', menu: 'Меню', task: 'Задача', project: 'Проект', priority: 'Приоритет {priority}',
  openState: 'Открыта', completeState: 'Завершено', focused: 'В фокусе', current: 'Сейчас выполняется', future: 'Предстоит', overdue: 'Просрочено',
  allDay: 'Весь день', noDate: 'Без даты', deadline: 'Дедлайн', repeat: 'Повтор', tomorrow: 'Завтра', yesterday: 'Вчера',
  inboxHint: 'Собирайте задачи перед сортировкой.', emptyToday: 'На этот день задач нет', emptyUpcoming: 'Нет задач с датой',
  emptyCompleted: 'Завершенных задач пока нет.', count: 'Задачи', page: 'Страница', startFocus: 'Начать фокус',
  idle: 'Нет активной сессии', work: 'Работа', running: 'Выполняется', paused: 'На паузе', ready: 'Готово',
  choosePriority: 'Выберите приоритет',
  inbox: 'Входящее', today: 'Сегодня', upcoming: 'Предстоящее', completed: 'Завершенные задачи', focus: 'Фокус', account: 'Аккаунт',
  add: 'Добавить задачу', edit: 'Изменить название', note: 'Комментарий', date: 'Расписание', done: 'Завершить', undo: 'Сделать открытой',
  del: 'Удалить', yes: 'Удалить', back: 'Назад', refresh: 'Обновить', pause: 'Пауза', resume: 'Продолжить', stop: 'Стоп', finish: 'Завершить интервал',
  empty: 'Здесь нет задач', saved: 'Сохранено.', removed: 'Задача удалена', link: 'Подключить существующий аккаунт', linked: 'Подключён ваш аккаунт Pomodoist.',
  guest: 'Гость Telegram. Подключите существующий аккаунт для синхронизации с основным приложением.', open: 'Открыть Pomodoist',
  help: 'Отправьте сообщение, чтобы добавить задачу. Откройте задачу из списка, чтобы изменить, выполнить, запланировать или удалить её.\n\n/inbox /today /upcoming /completed\n/focus /pause /resume /stop /finish\n/account /help /cancel\n\nДата без времени: YYYY-MM-DD; clear снимает дату. Название и комментарий можно вводить ответом на запрос бота. Здесь доступны задачи всего аккаунта, а не только созданные в Telegram.',
  confirm: 'Удалить эту задачу и её подзадачи?', newPrompt: 'Ответьте названием задачи или отправьте /cancel.',
  editPrompt: 'Ответьте новым названием задачи или отправьте /cancel.', notePrompt: 'Ответьте текстом комментария (clear удаляет его) или отправьте /cancel.',
  datePrompt: 'Ответьте датой YYYY-MM-DD без времени (она заменит дату со временем). clear снимает дату, /cancel возвращает в меню.',
  noFocus: 'Откройте задачу и нажмите «Начать фокус», чтобы начать 25-минутный рабочий интервал.',
  focusNote: 'Таймер продолжается после закрытия чата. «Обновить» покажет остаток времени. Завершение доступно только после окончания интервала.',
  error: 'Не удалось выполнить действие. Обновите список и повторите попытку.', changed: 'Задача изменилась. Обновите карточку перед редактированием.',
  expired: 'Эта кнопка устарела. Откройте новый список задач или /focus.', notFound: 'Задача не найдена. Обновите список.',
  recurring: 'Удаляйте повторяющиеся задачи и снимайте повторение в основном приложении. Задачи не изменены.',
  tooLarge: 'У задачи слишком много подзадач для одного действия. Откройте Pomodoist, чтобы изменить их. Ничего не изменено.',
  activeFocus: 'Перед удалением остановите активный Фокус этой задачи.', focusChanged: 'Состояние Фокуса изменилось. Откройте /focus.',
  notElapsed: 'Интервал ещё не закончился. Откройте /focus, чтобы проверить остаток времени.', invalid: 'Некорректный ввод. Используйте кнопки или /help.',
};
export type Copy = typeof en;
// Mapped strings are checked against Flutter ARB files by bot_copy_test.ts.
export const appCopyKeys = {
  inbox: 'navInbox', today: 'navToday', upcoming: 'navUpcoming', focus: 'navFocus', account: 'account',
  completed: 'completedTasks', add: 'addTask', note: 'taskComment', date: 'scheduleTitle', done: 'markComplete', undo: 'markOpen',
  del: 'commonDelete', cancel: 'commonCancel', back: 'commonBack', stop: 'commonStop',
  pause: 'pause', resume: 'resume', finish: 'completeInterval', removed: 'taskDeleted',
  allDay: 'allDay', noDate: 'noDate', repeat: 'recurrenceTitle', priority: 'priority', startFocus: 'startFocus',
  tomorrow: 'tomorrow', yesterday: 'yesterday', completeState: 'taskTimeStatusCompleted',
  focused: 'taskTimeStatusFocused', current: 'taskTimeStatusCurrent', future: 'taskTimeStatusFuture', overdue: 'taskTimeStatusOverdue',
  idle: 'noActiveSession', work: 'work', running: 'focusStatusRunning', paused: 'focusStatusPaused', ready: 'readyShort',
  inboxHint: 'screenInboxSubtitle', menu: 'menuTooltip', empty: 'noTasksHere', emptyToday: 'noTasksForDay', emptyUpcoming: 'noUpcomingTasks',
} as const;
export function copy(language: unknown) { return String(language ?? '').toLowerCase().startsWith('ru') ? ru : en; }
export function navigation(t: Copy): Button[][] {
  return [[{ text: t.today, callback_data: 'list:today:0' }, { text: t.upcoming, callback_data: 'list:upcoming:0' }, { text: t.inbox, callback_data: 'list:inbox:0' }],
    [{ text: t.focus, callback_data: 'focus' }, { text: t.completeState, callback_data: 'list:completed:0' }, { text: t.account, callback_data: 'account' }],
    [{ text: `＋ ${t.add}`, callback_data: 'new' }]];
}
const actions = new Set(['view', 'done', 'undo', 'edit', 'note', 'date', 'del', 'yes', 'go', 'pause', 'resume', 'stop', 'finish', 'priority', 'pone', 'ptwo', 'pthree', 'pfour']);
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
/** Static screens share the same hierarchy; user strings are never parsed as HTML. */
export function messageScreen(title: string, body: string, rows: Button[][]): Screen {
  const message = new Message().add(`Pomodoist · ${title}`, 'bold').add(`\n\n${body}`);
  return { ...message, reply_markup: { inline_keyboard: rows } };
}
export function withNotice(screen: Screen, notice: string): Screen {
  const prefix = `${shorten(notice, 200)}\n\n`;
  return { ...screen, text: prefix + screen.text, entities: (screen.entities ?? []).map(e => ({ ...e, offset: e.offset + prefix.length })) };
}
export function listScreen(snapshot: JsonMap, t: Copy, now: Date): Screen {
  const view = String(snapshot.view ?? 'inbox') as 'inbox' | 'today' | 'upcoming' | 'completed';
  const tasks = (Array.isArray(snapshot.tasks) ? snapshot.tasks as JsonMap[] : []).filter(task => uuidPattern.test(String(task.id))).slice(0, 6);
  const page = Number(snapshot.page ?? 0), pages = Number(snapshot.pages ?? 1);
  const message = new Message().add(`Pomodoist · ${t[view] ?? t.inbox}`, 'bold');
  message.add(`\n${t.count}: ${snapshot.total ?? 0} · ${t.page} ${page + 1}/${pages}`);
  if (view === 'inbox') message.add(`\n${t.inboxHint}`);
  if (!tasks.length) message.add(`\n\n${view === 'today' ? t.emptyToday : view === 'upcoming' ? t.emptyUpcoming : view === 'completed' ? t.emptyCompleted : t.empty}`);
  const rows: Button[][] = tasks.map((task, index) => {
    const meta = taskMeta({ ...task, timeZone: snapshot.timeZone ?? task.timeZone }, t, now);
    message.add(`\n\n${index + 1}. ${oneLine(task.content, 100)}`, task.status === 'completed' ? 'strikethrough' : 'bold');
    message.add(`\n${shorten(`${meta.state} · P${meta.priority} · ${meta.schedule}`, 240)}`);
    if (meta.deadline) message.add(`\n${t.deadline}: ${meta.deadline}`);
    return [{ text: `${index + 1}. ${task.status === 'completed' ? '✓' : '○'} ${oneLine(task.content, 45)}`,
      callback_data: actionData('view', String(task.id), Number(task.revision ?? 0), now) }];
  });
  const paging: Button[] = [];
  if (page > 0) paging.push({ text: '←', callback_data: `list:${view}:${page - 1}` });
  paging.push({ text: t.refresh, callback_data: `list:${view}:${page}` });
  if (page + 1 < pages) paging.push({ text: '→', callback_data: `list:${view}:${page + 1}` });
  return { ...message, reply_markup: { inline_keyboard: [...rows, paging, ...navigation(t)] } };
}
export function taskScreen(task: JsonMap | null, t: Copy, now: Date, confirm = false): Screen {
  if (!task) throw new TelegramError('task_not_found', 404);
  const button = (action: string, title: string): Button => ({ text: title, callback_data: actionData(action, String(task.id), Number(task.revision ?? 0), now) });
  const meta = taskMeta(task, t, now);
  const message = new Message().add(`Pomodoist · ${confirm ? t.del : t.task}`, 'bold');
  if (confirm) message.add(`\n\n${t.confirm}`);
  message.add(`\n\n${shorten(task.content, 1800)}`, task.status === 'completed' ? 'strikethrough' : 'bold');
  message.add(`\n${meta.state} · ${t.priority.replace('{priority}', String(meta.priority))}`);
  message.add(`\n${t.project}: ${task.projectId === 'inbox' ? t.inbox : oneLine(task.projectName, 100) || t.project}`);
  message.add(`\n${t.date}: ${meta.schedule}`);
  if (meta.deadline) message.add(`\n${t.deadline}: ${meta.deadline}`);
  if (meta.repeating) message.add(`\n↻ ${t.repeat}`);
  if (task.description) message.add(`\n\n${t.note}`, 'bold').add(`\n${shorten(task.description, 900)}`);
  const rows = confirm ? [[button('view', t.cancel), button('yes', t.del)]] : [
    [task.status === 'completed' ? button('undo', t.undo) : button('done', t.done),
      ...(task.status === 'completed' ? [] : [button('go', t.startFocus)])],
    [button('edit', t.edit), button('note', t.note)],
    [button('date', t.date), button('priority', t.priority.replace('{priority}', String(meta.priority)))],
    [button('view', t.refresh), button('del', t.del)],
  ];
  return { ...message, reply_markup: { inline_keyboard: [...rows, ...navigation(t)] } };
}
export function priorityScreen(task: JsonMap | null, t: Copy, now: Date): Screen {
  if (!task) throw new TelegramError('task_not_found', 404);
  const row = ['pone', 'ptwo', 'pthree', 'pfour'].map((action, i) => ({
    text: `${Number(task.priority ?? 4) === i + 1 ? '✓ ' : ''}P${i + 1}`,
    callback_data: actionData(action, String(task.id), Number(task.revision ?? 0), now),
  }));
  return messageScreen(t.choosePriority, oneLine(task.content, 200), [row,
    [{ text: t.cancel, callback_data: actionData('view', String(task.id), Number(task.revision ?? 0), now) }], ...navigation(t)]);
}
export function focusScreen(snapshot: JsonMap, t: Copy, now: Date): Screen {
  const focus = object(snapshot.focus), run = object(focus?.run), interval = object(focus?.interval);
  if (!run || !interval) return messageScreen(t.focus, `${t.idle}\n\n${t.noFocus}`, navigation(t));
  const paused = interval.status === 'paused';
  const start = new Date(interval.startedAt as string).getTime();
  const effective = paused ? new Date(interval.pausedAt as string).getTime() : +now;
  const elapsed = Math.max(0, Math.floor((effective - start) / 1000) - Number(interval.pausedTotalSeconds ?? 0));
  const seconds = Math.max(0, Number(interval.plannedSeconds ?? 1500) - elapsed);
  const clock = `${Math.floor(seconds / 60).toString().padStart(2, '0')}:${Math.floor(seconds % 60).toString().padStart(2, '0')}`;
  const b = (action: string, title: string) => ({ text: title, callback_data: actionData(action, String(run.id), 0, now) });
  const message = new Message().add(`Pomodoist · ${t.focus}`, 'bold');
  const task = object(snapshot.focusTask);
  if (task) message.add(`\n\n${shorten(task.content, 500)}`, 'bold');
  message.add(`\n${t.work} · ${seconds === 0 ? t.ready : paused ? t.paused : t.running}`);
  message.add(`\n\n${clock}`, 'code').add(`\n\n${t.focusNote}`);
  return { ...message, reply_markup: { inline_keyboard: [[b(paused ? 'resume' : 'pause', paused ? t.resume : t.pause), b('stop', t.stop)],
    ...(seconds === 0 ? [[b('finish', t.finish)]] : []), [{ text: t.refresh, callback_data: 'focus' }],
    ...(task && uuidPattern.test(String(task.id)) ? [[{ text: t.task, callback_data: actionData('view', String(task.id), Number(task.revision ?? 0), now) }]] : []), ...navigation(t)] } };
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
