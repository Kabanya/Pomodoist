/** Telegram adapters for the existing schema-v1 synchronization contract. */
export type JsonMap = Record<string, unknown>;
export type State = {
  tasks: Map<string, JsonMap>;
  projects: Map<string, JsonMap>;
  focusRuns: Map<string, JsonMap>;
  focusIntervals: Map<string, JsonMap>;
  entities: { entityType: string; entityId: string; serverRevision: number; data: JsonMap }[];
};
export type Operation = {
  opId: string; entityType: string; entityId: string;
  operation: 'upsert' | 'delete'; payload: JsonMap; clientUpdatedAt: string;
};
export type SnapshotOptions = { view?: string; page?: number; timeZone?: string; taskId?: string };
export class TelegramError extends Error {
  readonly code: string;
  readonly status: number;
  constructor(code: string, status = 400) { super(code); this.code = code; this.status = status; }
}
export function object(value: unknown): JsonMap | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value) ? value as JsonMap : null;
}
export const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function text(value: unknown, max: number, code: string): string {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new TelegramError(code);
  return value;
}
export function validDate(value: unknown): value is string {
  return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value) &&
    Number.isFinite(Date.parse(`${value}T00:00:00Z`)) && new Date(`${value}T00:00:00Z`).toISOString().slice(0, 10) === value;
}
function due(raw: unknown): JsonMap | null {
  if (typeof raw !== 'string') return null;
  try { return object(JSON.parse(raw)); } catch { return null; }
}
function validateDue(raw: unknown) {
  if (raw === null) return;
  const s = due(raw);
  const iso = (value: unknown) => typeof value === 'string' && validDate(value.slice(0, 10)) && /^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:[0-5]\d)$/.test(value) && Number.isFinite(Date.parse(value));
  if (typeof raw !== 'string' || raw.length > 8192 || !s ||
      !(s.type === 'allDay' && validDate(s.date) || s.type === 'timed' && iso(s.start) && iso(s.end) && Date.parse(String(s.end)) > Date.parse(String(s.start)))) {
    throw new TelegramError('invalid_task_schedule');
  }
}
export function validateCommand(command: JsonMap | null): asserts command is JsonMap {
  const types = ['task.create', 'task.update', 'task.delete', 'task.complete', 'task.uncomplete', 'focus.start', 'focus.pause', 'focus.resume', 'focus.stop', 'focus.complete'];
  if (!command || !types.includes(String(command.type))) throw new TelegramError('unsupported_command');
  if (!uuidPattern.test(String(command.id))) throw new TelegramError('invalid_command_id');
  if (command.type === 'task.create') text(command.content, 2000, 'invalid_task_content');
  if (command.type !== 'task.create' && (String(command.type).startsWith('task.') || command.type === 'focus.start' && command.taskId != null)) {
    if (!uuidPattern.test(String(command.taskId))) throw new TelegramError('invalid_task_id');
  }
  for (const key of ['runId', 'intervalId']) {
    if (command[key] !== undefined && !uuidPattern.test(String(command[key]))) throw new TelegramError('invalid_focus_id');
  }
  if (command.expectedRevision !== undefined && (!Number.isSafeInteger(command.expectedRevision) || Number(command.expectedRevision) < 0)) throw new TelegramError('invalid_task_revision');
  if (command.type === 'task.update') {
    const patch = object(command.patch);
    if (!patch || Object.keys(patch).length === 0) throw new TelegramError('invalid_task_patch');
    for (const [key, value] of Object.entries(patch)) {
      if (key === 'content') text(value, 2000, 'invalid_task_content');
      else if (key === 'description') {
        if (value !== null && (typeof value !== 'string' || value.length > 8000)) throw new TelegramError('invalid_task_description');
      } else if (key === 'priority') {
        if (!Number.isInteger(value) || Number(value) < 1 || Number(value) > 4) throw new TelegramError('invalid_task_priority');
      } else if (key === 'dueJson') validateDue(value);
      else throw new TelegramError('invalid_task_patch');
    }
  }
}
export function snapshotOptions(value: JsonMap = {}): SnapshotOptions {
  const options: SnapshotOptions = {};
  if (value.view !== undefined) {
    if (!['inbox', 'today', 'upcoming', 'completed'].includes(String(value.view))) throw new TelegramError('invalid_view');
    options.view = String(value.view);
  }
  if (value.page !== undefined) {
    if (!Number.isSafeInteger(value.page) || Number(value.page) < 0 || Number(value.page) > 100000) throw new TelegramError('invalid_page');
    options.page = Number(value.page);
  }
  if (value.timeZone !== undefined) {
    try {
      options.timeZone = text(value.timeZone, 100, 'invalid_time_zone');
      new Intl.DateTimeFormat('en', { timeZone: options.timeZone }).format();
    } catch { throw new TelegramError('invalid_time_zone'); }
  }
  if (value.taskId !== undefined) {
    if (!uuidPattern.test(String(value.taskId))) throw new TelegramError('invalid_task_id');
    options.taskId = String(value.taskId);
  }
  return options;
}
function active(row: JsonMap) { return !row.isDeleted && ['active', 'paused'].includes(String(row.status)); }
function subtree(state: State, root: JsonMap) {
  const children = new Map<string, JsonMap[]>();
  for (const row of state.tasks.values()) {
    if (!row.isDeleted && row.parentId) children.set(String(row.parentId), [...children.get(String(row.parentId)) ?? [], row]);
  }
  const rows: JsonMap[] = [], stack = [root], seen = new Set();
  while (stack.length) {
    const row = stack.pop()!;
    if (seen.has(row.id)) continue;
    seen.add(row.id); rows.push(row);
    stack.push(...(children.get(String(row.id)) ?? []).sort((a, b) => String(b.id).localeCompare(String(a.id))));
  }
  return rows;
}
// Match the deterministic UUID sequence already used by the Telegram adapter.
function entityUuid(commandId: string, sequence: number) {
  const raw = commandId.replaceAll('-', '').toLowerCase();
  const suffix = (BigInt(`0x${raw.slice(20)}`) ^ BigInt(sequence)).toString(16).padStart(12, '0');
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-5${raw.slice(13, 16)}-${((parseInt(raw[16], 16) & 3) | 8).toString(16)}${raw.slice(17, 20)}-${suffix}`;
}
function previousStatus(state: State, taskId: string) {
  const entry = state.entities.find(e => e.entityType === 'task_kanban_status' && e.entityId === taskId);
  return entry?.data.labelId && entry.data.labelId !== 'kanban-status-done-v1' ? entry.data.labelId : 'kanban-status-backlog-v1';
}
/** Returns null only for commands delegated to the established create/Focus logic. */
export function taskOperations(state: State, command: JsonMap, now: Date): Operation[] | null {
  validateCommand(command);
  const type = String(command.type), id = String(command.taskId);
  if (type.startsWith('focus.')) {
    const run = [...state.focusRuns.values()].find(active);
    if (type === 'focus.start') {
      const task = state.tasks.get(id);
      if (command.taskId != null && (!task || task.isDeleted || task.status === 'completed')) throw new TelegramError('task_not_found', 404);
      if (run) throw new TelegramError('focus_already_active', 409);
    } else {
      if (!run || command.runId !== undefined && command.runId !== run.id) throw new TelegramError('focus_changed', 409);
      const interval = [...state.focusIntervals.values()].find(row => row.runId === run.id && !row.isDeleted && ['running', 'paused'].includes(String(row.status)));
      if (!interval || command.intervalId !== undefined && command.intervalId !== interval.id) throw new TelegramError('focus_changed', 409);
      if (type === 'focus.pause' && interval.status !== 'running' || type === 'focus.resume' && interval.status !== 'paused') throw new TelegramError('focus_changed', 409);
    }
    return null;
  }
  if (type === 'task.create') return null;
  const task = state.tasks.get(id);
  if (!task || task.isDeleted) throw new TelegramError('task_not_found', 404);
  const revision = state.entities.find(e => e.entityType === 'task' && e.entityId === id)?.serverRevision ?? 0;
  if (command.expectedRevision !== undefined && command.expectedRevision !== revision) throw new TelegramError('task_changed', 409);
  const operations: Operation[] = [];
  const add = (entityType: string, entityId: string, payload: JsonMap, operation: 'upsert' | 'delete' = 'upsert') => {
    operations.push({ opId: operations.length === 0 ? String(command.id) : `${command.id}:${entityType}:${entityId}`,
      entityType, entityId, operation, payload: { schemaVersion: 1, commandType: type, ...payload }, clientUpdatedAt: now.toISOString() });
  };
  if (type === 'task.update') {
    const patch = { ...command.patch as JsonMap };
    if (typeof patch.content === 'string') patch.content = patch.content.trim();
    if ('dueJson' in patch) {
      const before = due(task.dueJson), after = due(patch.dueJson);
      if (before?.recurrence && !after) throw new TelegramError('recurring_task_requires_app', 409);
      if (after) {
        // Changing a date must not accidentally drop the recurrence relationship.
        for (const key of ['recurrence', 'recurrenceSeriesId']) if (before?.[key] !== undefined) after[key] = before[key];
        patch.dueJson = JSON.stringify(after);
      }
      patch.durationSeconds = after?.type === 'timed' ? (Date.parse(String(after.end)) - Date.parse(String(after.start))) / 1000 : null;
    }
    add('task', id, { id, ...patch, updatedAt: now.toISOString() });
    return operations;
  }
  const rows = subtree(state, task);
  if (type === 'task.delete') {
    if (rows.some(row => due(row.dueJson)?.recurrence || due(row.dueJson)?.recurrenceSeriesId)) throw new TelegramError('recurring_task_requires_app', 409);
    if ([...state.focusRuns.values()].some(run => active(run) && rows.some(row => row.id === run.taskId))) throw new TelegramError('task_has_active_focus', 409);
    for (const row of rows) add('task', String(row.id), { id: row.id, isDeleted: true, updatedAt: now.toISOString() }, 'delete');
  } else {
    const completing = type === 'task.complete';
    let sequence = 0;
    for (const row of rows) {
      if ((row.status === 'completed') === completing) continue;
      add('task', String(row.id), { id: row.id, status: completing ? 'completed' : 'open', completedAt: completing ? now.toISOString() : null, updatedAt: now.toISOString() });
      if (completing) {
        const completionId = entityUuid(String(command.id), ++sequence);
        add('task_completion', completionId, { id: completionId, taskId: row.id, userId: 'local-user', completedAt: now.toISOString(), createdAt: now.toISOString(),
          snapshotJson: JSON.stringify({ version: 1, kanban: { previousStatusLabelId: previousStatus(state, String(row.id)) } }) });
      }
    }
  }
  // The server RPC commits at most 50 operations in one transaction. Never split
  // subtree mutations: retries must not leave half a hierarchy deleted/completed.
  if (operations.length > 50) throw new TelegramError('task_batch_too_large', 409);
  return operations;
}
export function dayInZone(value: unknown, timeZone: string) {
  const date = new Date(value as string | number);
  if (!Number.isFinite(+date)) return '';
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const part = (type: string) => parts.find(p => p.type === type)?.value;
  return `${part('year')}-${part('month')}-${part('day')}`;
}
export function taskPage(state: State, now: Date, input: SnapshotOptions) {
  const options = snapshotOptions(input as JsonMap), view = options.view ?? 'inbox', timeZone = options.timeZone ?? 'UTC';
  const today = dayInZone(now.toISOString(), timeZone);
  const day = (task: JsonMap) => { const s = due(task.dueJson); return s?.type === 'allDay' ? String(s.date ?? '') : s?.type === 'timed' ? dayInZone(s.start, timeZone) : ''; };
  const visible = [...state.tasks.values()].filter(task => {
    const project = state.projects.get(String(task.projectId));
    return !task.isDeleted && !project?.isDeleted && !project?.isArchived;
  });
  const rows = visible.filter(task => {
    if (view === 'completed') return task.status === 'completed';
    if (task.status === 'completed') return false;
    const d = day(task);
    return view === 'inbox' ? task.projectId === 'inbox' : view === 'today' ? d !== '' && d <= today : d > today;
  }).sort((a, b) => view === 'completed' ? new Date(b.completedAt as string).getTime() - new Date(a.completedAt as string).getTime() :
    day(a).localeCompare(day(b)) || String(a.orderKey ?? '').localeCompare(String(b.orderKey ?? '')) || String(a.id).localeCompare(String(b.id)));
  const pages = Math.max(1, Math.ceil(rows.length / 6)), page = Math.min(options.page ?? 0, pages - 1);
  const revisions = new Map(state.entities.filter(e => e.entityType === 'task').map(e => [e.entityId, e.serverRevision]));
  const focusTaskId = [...state.focusRuns.values()].find(active)?.taskId;
  const summarize = (row: JsonMap, detail = false) => ({ id: String(row.id), content: String(row.content ?? ''), status: String(row.status ?? 'open'),
    timeZone, projectId: row.projectId ?? null, projectName: state.projects.get(String(row.projectId))?.name ?? null,
    deadlineJson: row.deadlineJson ?? null, isFocused: row.id === focusTaskId,
    day: day(row), dueJson: row.dueJson ?? null, priority: row.priority ?? 4, revision: revisions.get(String(row.id)) ?? 0,
    ...(detail ? { description: row.description ?? null, parentId: row.parentId ?? null } : {}) });
  const selected = options.taskId ? visible.find(row => row.id === options.taskId) : undefined;
  const focusTask = visible.find(row => row.id === focusTaskId);
  return { focusTask: focusTask ? summarize(focusTask) : null, view, timeZone, total: rows.length, page, pages, tasks: rows.slice(page * 6, page * 6 + 6).map(row => summarize(row)), task: selected ? summarize(selected, true) : null };
}
export async function stableUuid(value: string) {
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value)));
  hash[6] = (hash[6] & 15) | 80; hash[8] = (hash[8] & 63) | 128;
  const h = [...hash.slice(0, 16)].map(n => n.toString(16).padStart(2, '0')).join('');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`;
}
