import { assertEquals } from '@std/assert';
import fixtures from '../../tool/tests/fixtures/companion_commands.json' with { type: 'json' };
import { pomodoistState } from '../supabase/functions/_shared/pomodoist_state.ts';
import { commitDraftOps } from '../supabase/functions/_shared/pomodoist_task_commands.ts';
import { focusStartOps } from '../supabase/functions/_shared/pomodoist_focus_commands.ts';
import { decodeTaskDrafts } from '../supabase/functions/_shared/task_decomposition.ts';
import { handlePomodoistAi } from '../supabase/functions/pomodoist-ai/pomodoist_ai.ts';

Deno.test('shared command fixtures retain drafts, batch links, Focus and sync payloads', async () => {
  const now = new Date(fixtures.ai.request.command.currentLocalTime);
  assertEquals(decodeTaskDrafts(JSON.parse(fixtures.ai.providerResponse.choices[0].message.content).tasks), fixtures.ai.response.tasks);
  const ops = await commitDraftOps(pomodoistState([]), fixtures.batch, { id: 'user' }, now, () => crypto.randomUUID());
  assertEquals(ops.filter(op => op.entityType === 'task').length, 2);
  assertEquals(ops.filter(op => op.entityType === 'label').length, 1);
  assertEquals(ops.filter(op => op.entityType === 'task_label').length, 2);
  const state = pomodoistState([{ ...fixtures.sync, data: fixtures.sync.payload }]);
  assertEquals(state.tasks.get(fixtures.sync.entityId)?.dueJson, null);
  const focus = focusStartOps(state, fixtures.focus.command, { id: 'user' }, now, () => crypto.randomUUID());
  assertEquals(focus.find(op => op.entityType === 'focus_run')?.payload.status, fixtures.focus.runStatus);
  assertEquals(focus.find(op => op.entityType === 'focus_interval')?.payload.plannedSeconds, fixtures.focus.plannedSeconds);
  assertEquals(focus.find(op => op.entityType === 'focus_interval')?.payload.status, fixtures.focus.intervalStatus);
});
Deno.test('shared unauthorized request keeps its error contract', async () => {
  const response = await handlePomodoistAi(new Request('https://example.test', {
    method: 'POST', body: JSON.stringify(fixtures.unauthorized.request),
  }), { env: { get: () => undefined }, fetch, createClient: () => { throw Error('No bearer token'); } });
  assertEquals(response.status, fixtures.unauthorized.status);
  assertEquals((await response.json()).code, fixtures.unauthorized.code);
});
