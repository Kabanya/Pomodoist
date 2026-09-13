// The wire format follows app_account v0.2.0 and AccountSyncEngine (schema v1).
export const APP_ID = 'pomodoist';
const BACKLOG = 'kanban-status-backlog-v1';
const DONE = 'kanban-status-done-v1';
export const cachedTypes = new Set(['task', 'project', 'label', 'task_completion', 'task_kanban_status']);
export const keyOf = (type, id) => `${type}:${id}`;
export const recordsOf = (records, type) => Object.entries(records)
  .filter(([key, row]) => key.startsWith(`${type}:`) && !row.isDeleted)
  .map(([, row]) => row);
export const dateKey = (date = new Date()) => [date.getFullYear(),
  String(date.getMonth() + 1).padStart(2, '0'), String(date.getDate()).padStart(2, '0')].join('-');

export function parseDue(raw) {
  if (!raw) return null;
  try {
    const s = JSON.parse(raw);
    if (s.type === 'allDay' && validDate(s.date)) return s;
    if (s.type === 'timed' && Number.isFinite(Date.parse(s.start)) && Date.parse(s.end) > Date.parse(s.start)) return s;
  } catch { /* Unknown schedules remain untouched until explicitly edited. */ }
  return null;
}
function validDate(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T12:00:00`);
  return Number.isFinite(+d) && dateKey(d) === value;
}
export function dueDay(task) {
  const s = parseDue(task.dueJson);
  return !s ? '' : s.type === 'allDay' ? s.date : dateKey(new Date(s.start));
}
export function tasksFor(records, view, now = Date.now()) {
  const today = dateKey(new Date(now));
  return recordsOf(records, 'task').filter(task => {
    const project = records[keyOf('project', task.projectId)];
    if (project?.isDeleted || project?.isArchived) return false;
    if (view === 'completed') return task.status === 'completed';
    if (task.status !== 'open') return false;
    const day = dueDay(task);
    if (view === 'today') return day !== '' && day <= today;
    if (view === 'upcoming') return day > today;
    return task.projectId === 'inbox';
  }).sort((a, b) => view === 'completed'
    ? (new Date(b.completedAt).getTime() || 0) - (new Date(a.completedAt).getTime() || 0)
    : dueDay(a).localeCompare(dueDay(b)) || (a.dayOrder ?? 0) - (b.dayOrder ?? 0) ||
      String(a.orderKey).localeCompare(String(b.orderKey)) || a.id.localeCompare(b.id));
}
export function scheduleFields(raw) {
  const s = parseDue(raw);
  if (!s) return { date: '', time: '', minutes: 30 };
  if (s.type === 'allDay') return { date: s.date, time: '', minutes: 30 };
  const start = new Date(s.start);
  return { date: dateKey(start), time: `${String(start.getHours()).padStart(2, '0')}:${String(start.getMinutes()).padStart(2, '0')}`,
    minutes: (Date.parse(s.end) - +start) / 60000 };
}
export function schedule(date, time, minutes, previous) {
  if (!date) {
    if (parseDue(previous)?.recurrence) throw new Error('Remove repeating schedules in the full app.');
    if (time) throw new Error('Choose a date before setting a time.');
    return null;
  }
  if (!validDate(date)) throw new Error('Invalid calendar date.');
  const old = parseDue(previous);
  const metadata = {};
  if (old?.recurrence) metadata.recurrence = old.recurrence;
  if (old?.recurrenceSeriesId) metadata.recurrenceSeriesId = old.recurrenceSeriesId;
  if (time === undefined && old?.type === 'timed') {
    const start = new Date(old.start);
    const [year, month, day] = date.split('-').map(Number);
    start.setFullYear(year, month - 1, day);
    return JSON.stringify({ ...old, start: start.toISOString(),
      end: new Date(+start + Date.parse(old.end) - Date.parse(old.start)).toISOString() });
  }
  if (!time) return JSON.stringify({ type: 'allDay', date, ...metadata });
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(time)) throw new Error('Invalid time.');
  if (!Number.isFinite(Number(minutes)) || minutes <= 0 || minutes > 10080) throw new Error('Duration must be between 1 and 10080 minutes.');
  const start = new Date(`${date}T${time}:00`);
  // Reject nonexistent wall times at a daylight-saving transition.
  if (dateKey(start) !== date || start.getHours() !== Number(time.slice(0, 2)) || start.getMinutes() !== Number(time.slice(3))) {
    throw new Error('This local time does not exist. Choose another time.');
  }
  return JSON.stringify({ type: 'timed', start: start.toISOString(),
    end: new Date(+start + Number(minutes) * 60000).toISOString(),
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone, ...metadata });
}
function content(value) {
  if (typeof value !== 'string' || !value.trim() || value.trim().length > 2048) throw new Error('Task title must contain 1–2048 characters.');
  return value.trim();
}
function checkedDue(raw) {
  if (raw === null) return null;
  if (typeof raw !== 'string' || raw.length > 16384 || !parseDue(raw)) throw new Error('Invalid schedule.');
  return raw;
}
function statusBefore(records, id) {
  const labelId = records[keyOf('task_kanban_status', id)]?.labelId;
  return validStatus(records, labelId) ? labelId : BACKLOG;
}
function validStatus(records, id) {
  const label = records[keyOf('label', id)];
  return id === BACKLOG || (label && !label.isDeleted && label.kind === 'kanbanStatus' && label.systemKey !== 'done');
}
function restoreStatus(records, id) {
  for (const completion of recordsOf(records, 'task_completion').filter(c => c.taskId === id)
    .sort((a, b) => new Date(b.completedAt) - new Date(a.completedAt))) {
    try {
      const snapshot = JSON.parse(completion.snapshotJson);
      const status = snapshot?.version === 1 && snapshot.kanban?.previousStatusLabelId;
      if (status && validStatus(records, status)) return status;
    } catch { /* Older completion records may not contain a workflow snapshot. */ }
  }
  return BACKLOG;
}
export function taskOperations(records, action, now = Date.now(), uuid = () => crypto.randomUUID()) {
  const iso = new Date(now).toISOString();
  const op = (entityType, entityId, payload, commandType) => ({ opId: uuid(), entityType, entityId,
    operation: 'upsert', payload: { schemaVersion: 1, ...(commandType ? { commandType } : {}), ...payload }, clientUpdatedAt: iso });
  const status = (id, labelId) => op('task_kanban_status', id, { taskId: id, labelId, changedAt: iso }, 'task.kanbanStatus.set');
  if (action.kind === 'create') {
    const id = uuid();
    const dueJson = checkedDue(action.dueJson ?? null);
    const description = action.description ?? null;
    if (description !== null && (typeof description !== 'string' || description.length > 8192)) throw new Error('Description is too long.');
    const row = { id, userId: 'local-user', content: content(action.content), description,
      projectId: 'inbox', sectionId: null, parentId: null, priority: 4, dueJson, deadlineJson: null,
      durationSeconds: parseDue(dueJson)?.type === 'timed' ? (Date.parse(parseDue(dueJson).end) - Date.parse(parseDue(dueJson).start)) / 1000 : null,
      status: 'open', estimatedFocusIntervals: null, completedFocusIntervals: 0, totalFocusSeconds: 0,
      orderKey: String(now * 1000).padStart(20, '0'), dayOrder: null, isCollapsed: false, isDeleted: false,
      createdAt: now, updatedAt: now, completedAt: null };
    return [op('task', id, row, 'task.create'), status(id, BACKLOG)];
  }
  const task = records[keyOf('task', action.id)];
  if (!task || task.isDeleted) throw new Error('Task is no longer available. Refresh the list.');
  if (action.kind === 'edit') {
    const patch = {};
    if (!action.patch || Array.isArray(action.patch)) throw new Error('Invalid task edit.');
    for (const [key, value] of Object.entries(action.patch)) {
      if (key === 'content') patch.content = content(value);
      else if (key === 'description' && (value === null || (typeof value === 'string' && value.length <= 8192))) patch.description = value;
      else if (key === 'priority' && Number.isInteger(value) && value >= 1 && value <= 4) patch.priority = value;
      else if (key === 'dueJson') {
        patch.dueJson = checkedDue(value);
        const s = parseDue(value);
        patch.durationSeconds = s?.type === 'timed' ? (Date.parse(s.end) - Date.parse(s.start)) / 1000 : null;
      } else throw new Error('Unsupported task field.');
    }
    if (!Object.keys(patch).length) return [];
    return [op('task', task.id, { id: task.id, ...patch, updatedAt: now }, 'task.update')];
  }
  if (!['complete', 'uncomplete'].includes(action.kind)) throw new Error('Unknown task action.');
  const tasks = recordsOf(records, 'task');
  const stack = [task], seen = new Set(), operations = [];
  while (stack.length) {
    const row = stack.pop();
    if (seen.has(row.id)) continue;
    seen.add(row.id);
    stack.push(...tasks.filter(child => child.parentId === row.id));
    const completing = action.kind === 'complete';
    if ((row.status === 'completed') === completing) continue;
    operations.push(op('task', row.id, { id: row.id, status: completing ? 'completed' : 'open',
      completedAt: completing ? iso : null, updatedAt: now }, `task.${action.kind}`));
    if (completing) {
      const completionId = uuid();
      operations.push(op('task_completion', completionId, { id: completionId, taskId: row.id, userId: 'local-user',
        completedAt: now, createdAt: now, snapshotJson: JSON.stringify({ version: 1, kanban: { previousStatusLabelId: statusBefore(records, row.id) } }) }));
    }
    operations.push(status(row.id, completing ? DONE : restoreStatus(records, row.id)));
  }
  return operations;
}
export function optimisticRecords(records, operations) {
  const next = { ...records };
  for (const op of operations) {
    const key = keyOf(op.entityType, op.entityId);
    if (!cachedTypes.has(op.entityType)) continue;
    if (op.operation === 'delete') delete next[key];
    else next[key] = { ...next[key], ...op.payload, id: op.entityId };
  }
  return next;
}
export function tabDraft(tab) {
  let url;
  try { url = new URL(tab?.url); } catch { throw new Error('This tab cannot be saved.'); }
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password) throw new Error('Only ordinary HTTP(S) pages can be saved.');
  if (url.href.length > 8192) throw new Error('This page URL is too long to save.');
  return { content: (tab.title?.trim() || url.hostname).slice(0, 512), description: url.href };
}
export function callbackValue(raw, redirect, state, name) {
  let url;
  try { url = new URL(raw); } catch { throw new Error('Sign-in was cancelled.'); }
  const expected = new URL(redirect);
  if (url.origin !== expected.origin || url.pathname !== expected.pathname || url.username || url.password || url.hash ||
      url.searchParams.getAll('state').length !== 1 || url.searchParams.get('state') !== state ||
      url.searchParams.getAll(name).length !== 1) throw new Error('Invalid sign-in callback. Please retry.');
  const value = url.searchParams.get(name);
  if (!value || value.length > 2048 || /[\u0000-\u001f\u007f-\u009f]/.test(value)) throw new Error('Invalid sign-in response.');
  return value;
}
