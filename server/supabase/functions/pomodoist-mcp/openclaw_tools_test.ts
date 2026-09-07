import { assert, assertEquals } from '@std/assert';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { registerOpenClawTools } from './openclaw_tools.ts';

const uuid = '11111111-1111-4111-8111-111111111111';
const config = { issuer: 'https://example.com/auth/v1', resourceUrl: 'https://example.com/mcp', allowedOrigins: [], supabaseUrl: 'https://example.com', serviceRoleKey: 'test-key' };
type Tool = { schema: z.ZodType; run: (args: unknown) => Promise<Record<string, unknown>> };
function fixture(entities: unknown[] = [], replay?: unknown) {
  const tools = new Map<string, Tool>();
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const server = { registerTool: (name: string, definition: { inputSchema: z.ZodType }, run: Tool['run']) => {
    tools.set(name, { schema: definition.inputSchema, run });
  } } as unknown as McpServer;
  registerOpenClawTools(server, { subject: uuid, sessionId: uuid, clientId: uuid, userId: uuid }, { config, fetch: async (input, init) => {
    const name = String(input).split('/').at(-1)!;
    const args = JSON.parse(String(init?.body)); calls.push({ name, args });
    if (name === 'pomodoist_openclaw_action') return Response.json(args.p_operations ? { ...args.p_result, server_revision: '2' } : { revision: '1', ...(replay ? { result: replay } : {}) });
    if (name === 'read_pomodoist_openclaw_state') return Response.json({ entities, serverNow: '2026-09-07T12:00:00Z' });
    if (name === 'read_pomodoist_mcp') return Response.json({ tasks: [], projects: [], labels: [], taskLabels: [], assignments: [], completions: [], settings: {} });
    if (name === 'send_pomodoist_mcp_sync_hint') return Response.json(null);
    throw new Error(`Unexpected RPC ${name}`);
  } });
  const invoke = async (name: string, value: unknown) => {
    const tool = tools.get(name)!;
    return await tool.run(tool.schema.parse(value));
  };
  return { tools, calls, invoke };
}
Deno.test('guarded create reuses MCP schema and plans before atomic commit', async () => {
  const { invoke, calls } = fixture();
  const response = await invoke('openclaw_create_task', { request_id: uuid, arguments: { content: 'Write tests', priority: 2, schedule: { type: 'all_day', date: '2026-09-08' } } });
  assertEquals((response.structuredContent as { ok: boolean }).ok, true);
  const commit = calls.find(call => Array.isArray(call.args.p_operations))!;
  const operations = commit.args.p_operations as { entityType: string; payload: Record<string, unknown> }[];
  const task = operations.find(op => op.entityType === 'task')!.payload;
  assertEquals(task.priority, 2);
  assertEquals(JSON.parse(String(task.dueJson)), { type: 'allDay', date: '2026-09-08' });
  assert(!calls.some(call => call.name === 'push_pomodoist_mcp_changes'));
  assertEquals(calls.at(-1)!.name, 'send_pomodoist_mcp_sync_hint');
});
Deno.test('delete needs explicit confirmation; nested original schema rejects empty updates', () => {
  const { tools } = fixture();
  assert(!tools.get('openclaw_delete_task')!.schema.safeParse({ request_id: uuid, arguments: { task_id: 'a' } }).success);
  assert(!tools.get('openclaw_update_task')!.schema.safeParse({ request_id: uuid, arguments: { task_id: 'a' } }).success);
});
Deno.test('replay never computes another task or starts another Focus run', async () => {
  const { invoke, calls } = fixture([], { id: 'saved', server_revision: '7' });
  const response = await invoke('openclaw_focus', { request_id: uuid, arguments: { action: 'start' } });
  assertEquals(response.structuredContent, { ok: true, data: { id: 'saved', server_revision: '7' } });
  assertEquals(calls.map(call => call.name), ['pomodoist_openclaw_action', 'send_pomodoist_mcp_sync_hint']);
});
Deno.test('Focus start uses shared runtime and emits synchronized run, interval and events', async () => {
  const { invoke, calls } = fixture();
  const response = await invoke('openclaw_focus', { request_id: uuid, arguments: { action: 'start' } });
  assertEquals((response.structuredContent as { ok: boolean }).ok, true);
  const commit = calls.find(call => Array.isArray(call.args.p_operations))!;
  const operations = commit.args.p_operations as { entityType: string; payload: Record<string, unknown> }[];
  assertEquals(operations.filter(op => op.entityType === 'focus_run').length, 1);
  assertEquals(operations.find(op => op.entityType === 'focus_interval')!.payload.plannedSeconds, 1500);
  assertEquals(operations.filter(op => op.entityType === 'focus_event').length, 2);
});
Deno.test('Focus controls require run and interval identities and stop confirmation', () => {
  const { tools } = fixture(); const schema = tools.get('openclaw_focus')!.schema;
  assert(!schema.safeParse({ request_id: uuid, arguments: { action: 'pause' } }).success);
  assert(!schema.safeParse({ request_id: uuid, arguments: { action: 'stop', run_id: 'run', interval_id: 'interval' } }).success);
});
Deno.test('a stale Focus command cannot control a different run', async () => {
  const { invoke, calls } = fixture();
  const response = await invoke('openclaw_focus', { request_id: uuid, arguments: { action: 'pause', run_id: 'old', interval_id: 'old' } });
  assertEquals((response.structuredContent as { error: { code: string } }).error.code, 'conflict');
  assert(!calls.some(call => call.args.p_operations));
});
Deno.test('deadline details preserve the Flutter date-only representation', async () => {
  const { invoke, calls } = fixture([{ entity_type: 'task', entity_id: 'task-1', server_revision: 1, data: { id: 'task-1', content: 'Read', status: 'open' } }]);
  await invoke('openclaw_set_task_details', { request_id: uuid, arguments: { task_id: 'task-1', deadline_date: '2028-02-29', duration_seconds: 1800 } });
  const commit = calls.find(call => Array.isArray(call.args.p_operations))!;
  const payload = (commit.args.p_operations as { payload: Record<string, unknown> }[])[0].payload;
  assertEquals(JSON.parse(String(payload.deadlineJson)), { type: 'date', date: '2028-02-29T00:00:00.000' });
  assertEquals(payload.durationSeconds, 1800);
});
Deno.test('deadline validation rejects impossible dates and no-op detail edits', () => {
  const { tools } = fixture(); const schema = tools.get('openclaw_set_task_details')!.schema;
  assert(!schema.safeParse({ request_id: uuid, arguments: { task_id: 'a', deadline_date: '2026-02-29' } }).success);
  assert(!schema.safeParse({ request_id: uuid, arguments: { task_id: 'a' } }).success);
});
const activeEntities = [
  { entity_type: 'focus_run', entity_id: 'run', server_revision: 1, data: { id: 'run', status: 'active', presetId: 'locked', endedAt: null } },
  { entity_type: 'focus_interval', entity_id: 'interval', server_revision: 2, data: { id: 'interval', runId: 'run', status: 'running', type: 'work', startedAt: '2026-09-07T11:59:00Z', plannedSeconds: 1500 } },
];
Deno.test('Focus cannot fabricate completion before the timer elapses', async () => {
  const { invoke, calls } = fixture(activeEntities);
  const response = await invoke('openclaw_focus', { request_id: uuid, arguments: { action: 'complete', run_id: 'run', interval_id: 'interval' } });
  assertEquals((response.structuredContent as { error: { message: string } }).error.message, 'Focus interval has not elapsed.');
  assert(!calls.some(call => call.args.p_operations));
});
Deno.test('Focus pause respects preset restrictions', async () => {
  const { invoke, calls } = fixture([...activeEntities, { entity_type: 'focus_preset', entity_id: 'locked', server_revision: 3, data: { id: 'locked', allowPause: false, strictMode: true } }]);
  const response = await invoke('openclaw_focus', { request_id: uuid, arguments: { action: 'pause', run_id: 'run', interval_id: 'interval' } });
  assertEquals((response.structuredContent as { error: { code: string } }).error.code, 'forbidden');
  assert(!calls.some(call => call.args.p_operations));
});
