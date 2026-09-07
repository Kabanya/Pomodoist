import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { type PomodoistMcpAuth, type ToolErrorCode, toolError, toolSuccess } from './pomodoist_mcp.ts';
import { registerPomodoistTools, type PomodoistToolDependencies } from './tools.ts';
import { pomodoistState, telegramCommandOps, telegramSnapshot } from '../pomodoist-watch/pomodoist_watch.ts';
import { ActionError, captureMutation, type JsonMap, type Plan, runGuardedAction } from './openclaw_actions.ts';

const mutations = ['create_task', 'update_task', 'complete_task', 'restore_task', 'delete_task',
  'create_project', 'update_project', 'delete_project', 'create_label', 'delete_label'] as const;
const entityId = z.string().regex(/^[A-Za-z0-9][A-Za-z0-9._:-]{0,199}$/);
const date = z.string().regex(/^\d{4}-\d{2}-\d{2}$/).refine(value => {
  const parsed = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(+parsed) && parsed.toISOString().slice(0, 10) === value;
}, 'Invalid calendar date.');
const details = z.object({ task_id: entityId, deadline_date: date.nullable().optional(),
  duration_seconds: z.number().int().min(1).max(604800).nullable().optional(),
}).strict().refine(value => value.deadline_date !== undefined || value.duration_seconds !== undefined,
  'At least one changed field is required.');
const focusArgs = z.object({ action: z.enum(['start', 'pause', 'resume', 'complete', 'stop']),
  task_id: entityId.optional(), run_id: entityId.optional(), interval_id: entityId.optional(), confirmed: z.literal(true).optional(),
}).strict().superRefine((value, context) => {
  if (value.action === 'start' ? value.run_id !== undefined || value.interval_id !== undefined
    : !value.run_id || !value.interval_id || value.task_id !== undefined) {
    context.addIssue({ code: 'custom', message: 'Start accepts task_id; controls require current run_id and interval_id.' });
  }
  if (value.action === 'stop' && value.confirmed !== true) {
    context.addIssue({ code: 'custom', message: 'Stopping Focus requires confirmation.' });
  }
});

type Captured = { schema: z.ZodType; run: (args: JsonMap) => Promise<unknown> };
// Capture existing registration callbacks, not private SDK fields. This keeps
// task validation, recurrence, kanban updates and sync payloads in one runtime.
function capture(auth: PomodoistMcpAuth, dependencies: PomodoistToolDependencies) {
  const tools = new Map<string, Captured>();
  const registrar = { registerTool(name: string, config: { inputSchema: z.ZodType }, run: Captured['run']) {
    tools.set(name, { schema: config.inputSchema, run });
  } };
  registerPomodoistTools(registrar as unknown as McpServer, auth, dependencies);
  return tools;
}

export function registerOpenClawTools(server: McpServer, auth: PomodoistMcpAuth, dependencies: PomodoistToolDependencies) {
  const fetcher = dependencies.fetch ?? fetch;
  const identity = { p_subject: auth.subject, p_session_id: auth.sessionId, p_client_id: auth.clientId };
  async function rpc(name: string, args: JsonMap): Promise<JsonMap> {
    const response = await fetcher(`${dependencies.config.supabaseUrl.replace(/\/+$/, '')}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: dependencies.config.serviceRoleKey,
        Authorization: `Bearer ${dependencies.config.serviceRoleKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(args), signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      if (['40001', '23505', '55P03', '40P01'].includes(body.code)) {
        throw new ActionError('conflict', 'State changed. Read the current task or Focus state before deciding on a new action.');
      }
      if (body.code === '42501' || response.status === 401 || response.status === 403) {
        throw new ActionError('forbidden', 'Access is no longer authorized. Reconnect Pomodoist.');
      }
      if (body.code === '22023') throw new ActionError('invalid_argument', 'Invalid action or reused request_id.');
      throw new ActionError('internal', 'Action status is uncertain. Retry with the same request_id and arguments.');
    }
    if (name === 'send_pomodoist_mcp_sync_hint') return {};
    const value = await response.json();
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new ActionError('internal', 'Invalid service response.');
    return value;
  }
  async function state(taskId?: string) {
    const value = await rpc('read_pomodoist_openclaw_state', { ...identity, p_task_id: taskId ?? null });
    if (!Array.isArray(value.entities) || typeof value.serverNow !== 'string' || !Number.isFinite(Date.parse(value.serverNow))) {
      throw new ActionError('internal', 'Invalid Focus snapshot.');
    }
    return { state: pomodoistState(value.entities), now: new Date(value.serverNow) };
  }
  function guarded(name: string, schema: z.ZodType, build: (args: JsonMap, requestId: string) => Promise<Plan>) {
    const destructive = name.startsWith('delete_');
    const input = z.object({ request_id: z.string().uuid(), arguments: schema,
      ...(destructive ? { confirmed: z.literal(true) } : {}),
    }).strict();
    server.registerTool(`openclaw_${name}`, {
      description: `Pomodoist ${name}. Reuse request_id and identical arguments after a timeout; never repeat with a new ID. ${destructive ? 'Ask for explicit confirmation first.' : ''}`,
      inputSchema: input,
      annotations: { readOnlyHint: false, idempotentHint: true, destructiveHint: destructive || name === 'focus', openWorldHint: false },
    }, async value => {
      try {
        const args = value.arguments as JsonMap;
        const result = await runGuardedAction(auth, { requestId: value.request_id, name, arguments: args },
          body => rpc('pomodoist_openclaw_action', body), () => build(args, value.request_id));
        try { await rpc('send_pomodoist_mcp_sync_hint', { p_user_id: auth.userId, p_client_id: auth.clientId }); }
        catch { /* Durable receipt is authoritative; a missed hint is repaired by pull. */ }
        return toolSuccess(result);
      } catch (error) { return failure(error); }
    });
  }
  for (const [name, tool] of capture(auth, dependencies)) {
    if (!(mutations as readonly string[]).includes(name)) continue;
    guarded(name, tool.schema, args => captureMutation(dependencies.config.supabaseUrl, fetcher, buffered => {
      const delegate = capture(auth, { ...dependencies, fetch: buffered }).get(name)!;
      return delegate.run(delegate.schema.parse(args) as JsonMap);
    }));
  }
  guarded('set_task_details', details, async args => {
    const current = await state(String(args.task_id));
    if (!current.state.tasks.has(String(args.task_id))) throw new ActionError('not_found', 'Task not found.');
    const timestamp = current.now.toISOString();
    const payload: JsonMap = { schemaVersion: 1, id: args.task_id, userId: 'local-user', commandType: 'task.update', updatedAt: timestamp };
    if (args.deadline_date !== undefined) payload.deadlineJson = args.deadline_date === null ? null
      : JSON.stringify({ type: 'date', date: `${args.deadline_date}T00:00:00.000` });
    if (args.duration_seconds !== undefined) payload.durationSeconds = args.duration_seconds;
    return { result: { id: args.task_id }, operations: [{ opId: crypto.randomUUID(), entityType: 'task', entityId: args.task_id,
      operation: 'upsert', payload, clientUpdatedAt: timestamp }] };
  });
  guarded('focus', focusArgs, async (args, requestId) => {
    const current = await state(args.task_id as string | undefined);
    const focus = telegramSnapshot(current.state, current.now).focus;
    if (args.action !== 'start' && (!focus || focus.run.id !== args.run_id || focus.interval.id !== args.interval_id)) {
      throw new ActionError('conflict', 'Focus changed. Read the current run and interval first.');
    }
    if (args.action === 'pause' && (focus?.preset.allowPause !== true || focus?.preset.strictMode === true)) {
      throw new ActionError('forbidden', 'This Focus preset does not allow pausing.');
    }
    let operations;
    try {
      operations = telegramCommandOps(current.state, { id: `openclaw:${auth.clientId}:${requestId}`,
        type: `focus.${args.action}`, ...(args.task_id ? { taskId: args.task_id } : {}) }, current.now, () => crypto.randomUUID());
    } catch (error) {
      if (error instanceof Error && error.message === 'Task not found.') throw new ActionError('not_found', error.message);
      const expected = ['Focus already active.', 'Completed tasks must be restored before Focus starts.',
        'Focus interval has not elapsed.', 'Focus is not active.', 'Focus interval is not running.', 'Focus interval is not paused.'];
      if (error instanceof Error && expected.includes(error.message)) throw new ActionError('conflict', error.message);
      throw error;
    }
    const runId = args.action === 'start' ? operations.find(op => op.entityType === 'focus_run')?.entityId : args.run_id;
    if (!runId) throw new ActionError('internal', 'Focus did not produce a run.');
    return { operations, result: { id: runId } };
  });
  server.registerTool('openclaw_get_focus', {
    description: 'Get the current synchronized Focus run, interval, preset and server time. Read before controlling Focus.',
    inputSchema: z.object({}).strict(), annotations: { readOnlyHint: true, openWorldHint: false },
  }, async () => {
    try {
      const current = await state(); const snapshot = telegramSnapshot(current.state, current.now);
      return toolSuccess({ generatedAt: snapshot.generatedAt, focus: snapshot.focus });
    } catch (error) { return failure(error); }
  });
  server.registerTool('openclaw_get_task', {
    description: 'Read a task including its separate deadline and duration. Scheduling and deadline are distinct.',
    inputSchema: z.object({ task_id: entityId }).strict(), annotations: { readOnlyHint: true, openWorldHint: false },
  }, async ({ task_id }) => {
    try {
      const current = await state(task_id); const task = current.state.tasks.get(task_id);
      if (!task) throw new ActionError('not_found', 'Task not found.');
      const fields = ['id', 'content', 'description', 'projectId', 'parentId', 'priority', 'dueJson', 'deadlineJson',
        'durationSeconds', 'status', 'estimatedFocusIntervals', 'completedFocusIntervals', 'totalFocusSeconds', 'updatedAt'];
      return toolSuccess(Object.fromEntries(fields.map(key => [key, task[key] ?? null])));
    } catch (error) { return failure(error); }
  });
}
function failure(error: unknown) {
  const codes = ['invalid_argument', 'not_found', 'conflict', 'forbidden', 'rate_limited', 'internal'];
  return error instanceof ActionError && codes.includes(error.code)
    ? toolError(error.code as ToolErrorCode, error.message)
    : toolError('internal', 'Action status is uncertain. Retry with the same request_id and arguments.');
}
