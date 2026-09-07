const en = {
  welcome: 'Pomodoist\n\nSend a message to add an Inbox task. Open the Mini App to organize tasks and focus.',
  open: 'Open Pomodoist', added: 'Added to Inbox.',
  invalid: 'Send a task title of 1–2000 characters.',
  error: 'Could not add the task. Please try again.',
};
const ru: typeof en = {
  welcome: 'Pomodoist\n\nОтправьте сообщение, чтобы добавить задачу во входящие. Управляйте задачами и фокусом в мини-приложении.',
  open: 'Открыть Pomodoist', added: 'Задача добавлена во входящие.',
  invalid: 'Отправьте название задачи длиной от 1 до 2000 символов.',
  error: 'Не удалось добавить задачу. Попробуйте ещё раз.',
};
export function copy(language: unknown) { return String(language ?? '').toLowerCase().startsWith('ru') ? ru : en; }
export function launcher(t: typeof en, url: string, text = t.welcome) {
  return { text, reply_markup: { inline_keyboard: [[{ text: t.open, web_app: { url } }]] } };
}
export type Screen = ReturnType<typeof launcher>;
