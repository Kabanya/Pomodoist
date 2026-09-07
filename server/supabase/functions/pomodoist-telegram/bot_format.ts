import { dayInZone, object, validDate, type JsonMap } from './commands.ts';
import type { Copy } from './bot_ui.ts';
export type Entity = { type: 'bold' | 'strikethrough' | 'code' | 'spoiler'; offset: number; length: number };
/** Telegram offsets count UTF-16 code units. Truncate before measuring, never split a surrogate pair. */
export function shorten(value: unknown, limit: number): string {
  const text = String(value ?? '');
  if (text.length <= limit) return text;
  const end = Math.max(0, limit - 1);
  return text.slice(0, end).replace(/[\uD800-\uDBFF]$/, '') + '…';
}
export function oneLine(value: unknown, limit: number) { return shorten(String(value ?? '').replace(/\s+/g, ' ').trim(), limit); }
export class Message {
  text = '';
  entities: Entity[] = [];
  add(value: string, type?: Entity['type']): this {
    // Leave room for a localized notice prepended after rendering a mutation.
    const remaining = 3800 - this.text.length;
    if (remaining <= 0) return this;
    const text = shorten(value, remaining);
    if (type && text.length) this.entities.push({ type, offset: this.text.length, length: text.length });
    this.text += text;
    return this;
  }
}
function json(value: unknown): JsonMap | null {
  if (typeof value !== 'string') return null;
  try { return object(JSON.parse(value)); } catch { return null; }
}
function zone(value: unknown) {
  const name = typeof value === 'string' ? value : 'UTC';
  try { new Intl.DateTimeFormat('en', { timeZone: name }); return name; } catch { return 'UTC'; }
}
function dateLabel(day: string, today: string, t: Copy) {
  if (day === today) return t.today;
  const delta = (Date.parse(`${day}T00:00:00Z`) - Date.parse(`${today}T00:00:00Z`)) / 86400000;
  return delta === 1 ? t.tomorrow : delta === -1 ? t.yesterday : day;
}
/** Mirrors lib/app/task_time.dart; deadlineJson never participates in scheduling or status. */
export function taskMeta(task: JsonMap, t: Copy, now: Date) {
  const timeZone = zone(task.timeZone), today = dayInZone(now.toISOString(), timeZone);
  const due = json(task.dueJson), deadline = json(task.deadlineJson);
  let schedule = t.noDate, state = t.openState;
  if (due?.type === 'allDay' && validDate(due.date)) {
    schedule = `${dateLabel(due.date, today, t)} · ${t.allDay}`;
    if (due.date < today) state = t.overdue;
  } else if (due?.type === 'timed' && typeof due.start === 'string' && typeof due.end === 'string' &&
      Number.isFinite(Date.parse(due.start)) && Date.parse(due.end) > Date.parse(due.start)) {
    const start = dayInZone(due.start, timeZone), end = dayInZone(due.end, timeZone);
    const clock = (value: string) => new Intl.DateTimeFormat('en-GB', { timeZone, hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(value));
    schedule = start === end ? `${dateLabel(start, today, t)} · ${clock(due.start)}–${clock(due.end)}` :
      `${dateLabel(start, today, t)} ${clock(due.start)}–${dateLabel(end, today, t)} ${clock(due.end)}`;
    schedule += ` · ${timeZone}`;
    state = +now < Date.parse(due.start) ? t.future : +now < Date.parse(due.end) ? t.current : t.overdue;
  }
  if (task.isFocused === true) state = t.focused;
  if (task.status === 'completed') state = t.completeState;
  const deadlineDay = deadline?.type === 'date' && typeof deadline.date === 'string' ? deadline.date.slice(0, 10) : '';
  const deadlineText = validDate(deadlineDay) ? dateLabel(deadlineDay, today, t) +
    (task.status !== 'completed' && deadlineDay < today ? ` · ${t.overdue}` : '') : '';
  const priority = Number.isInteger(task.priority) && Number(task.priority) >= 1 && Number(task.priority) <= 4 ? Number(task.priority) : 4;
  return { priority, state, schedule, deadline: deadlineText, repeating: !!(due?.recurrence || due?.recurrenceSeriesId) };
}
