import { assert, assertEquals } from '@std/assert';
import fixtures from '../../tool/tests/fixtures/companion_commands.json' with { type: 'json' };
import { pomodoistState } from '../supabase/functions/_shared/pomodoist_state.ts';
import { commitDraftOps } from '../supabase/functions/_shared/pomodoist_task_commands.ts';
import { focusStartOps } from '../supabase/functions/_shared/pomodoist_focus_commands.ts';
import { decodeTaskDrafts } from '../supabase/functions/_shared/task_decomposition.ts';
import { handlePomodoistAi } from '../supabase/functions/pomodoist-ai/pomodoist_ai.ts';

Deno.test('new shared migrations retain the hosted assembler naming contract', async () => {
  const manifest = JSON.parse(await Deno.readTextFile(new URL('../core-manifest.json', import.meta.url)));
  const baseline = new Set<string>(manifest.baselineMigrations);
  // Published before the shared prefix rule. This list is closed; applied
  // migration names must remain immutable while new migrations use the prefix.
  const legacy = new Set([
    '20260913000418_pomodoist_voice_quota_2500.sql',
    '20260913200049_pomodoist_llm_and_voice_quotas_1000.sql',
    '20260913201230_pomodoist_quota_readers_utc.sql',
    '20260913203151_pomodoist_subscription_offers.sql',
    '20260913222604_pomodoist_advisor_rpc_security.sql',
    '20260914104510_pomodoist_collaboration_consumers.sql',
    '20260924092625_pomodoist_storekit_transaction_order.sql',
    '20260925001954_pomodoist_kanban_sync.sql',
    '20260930154431_pomodoist_habits.sql',
    '20260930222811_pomodoist_session_revocation.sql',
    '20261003140901_pomodoist_habit_day_period.sql',
    '20261003205837_pomodoist_files_cleanup_auth_and_response.sql',
    '20261006160605_pomodoist_habit_icons.sql',
    '20261011222749_calendar_provider_connections.sql',
    '20261020092144_pomodoist_manual_focus_estimate.sql',
  ]);
  for await (const entry of Deno.readDir(new URL('../supabase/migrations', import.meta.url))) {
    if (!entry.isFile || !entry.name.endsWith('.sql') || baseline.has(entry.name)) continue;
    assert(legacy.has(entry.name) || /^\d{14}_pomodoist_core_[a-z0-9_]+\.sql$/.test(entry.name),
      `New shared migration requires pomodoist_core_ prefix: ${entry.name}`);
  }
});

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
