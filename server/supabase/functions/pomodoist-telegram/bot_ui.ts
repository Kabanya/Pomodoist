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
const pt: typeof en = {
  welcome: 'Pomodoist\n\nEnvie uma mensagem para adicionar uma tarefa à caixa de entrada. Abra o Mini App para organizar tarefas e se concentrar.',
  open: 'Abrir Pomodoist', added: 'Adicionada à caixa de entrada.',
  invalid: 'Envie um título de tarefa com 1 a 2000 caracteres.',
  error: 'Não foi possível adicionar a tarefa. Tente novamente.',
};
const ja: typeof en = {
  welcome: 'Pomodoist\n\nメッセージを送信すると、受信トレイにタスクを追加できます。ミニアプリを開いてタスクを整理し、集中しましょう。',
  open: 'Pomodoistを開く', added: '受信トレイに追加しました。',
  invalid: '1〜2000文字のタスク名を送信してください。',
  error: 'タスクを追加できませんでした。もう一度お試しください。',
};
const ko: typeof en = {
  welcome: 'Pomodoist\n\n메시지를 보내 받은 편지함에 작업을 추가하세요. 미니 앱을 열어 작업을 정리하고 집중하세요.',
  open: 'Pomodoist 열기', added: '받은 편지함에 추가했습니다.',
  invalid: '1~2000자의 작업 제목을 보내세요.',
  error: '작업을 추가하지 못했습니다. 다시 시도하세요.',
};
const messages: Record<string, typeof en> = { en, ru, pt, ja, ko };
export function copy(language: unknown) { const base = String(language ?? '').toLowerCase().split(/[-_]/)[0]; return Object.hasOwn(messages, base) ? messages[base] : en; }
export function launcher(t: typeof en, url: string, text = t.welcome) {
  return { text, reply_markup: { inline_keyboard: [[{ text: t.open, web_app: { url } }]] } };
}
export type Screen = ReturnType<typeof launcher>;
