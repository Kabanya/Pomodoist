import { assertEquals, assertRejects } from '@std/assert';
import { pomodoistMutationPlans } from './tools.ts';

Deno.test('mutation planners read and return operations without persisting or sending a hint', async () => {
  const calls: string[] = [];
  const plans = pomodoistMutationPlans(
    { subject: 'user', sessionId: 'session', clientId: 'client', userId: 'user' },
    { config: { issuer: 'https://example.com/auth/v1', resourceUrl: 'https://example.com/mcp',
      allowedOrigins: [], supabaseUrl: 'https://example.com', serviceRoleKey: 'test' },
      fetch: async input => {
        calls.push(String(input).split('/').at(-1)!);
        if (calls.at(-1) !== 'read_pomodoist_mcp') throw Error('Planner attempted a write');
        return Response.json({ tasks: [], projects: [], labels: [], taskLabels: [], assignments: [], completions: [] });
      },
    },
  );
  const create = plans.find(plan => plan.name === 'create_task')!;
  const plan = await create.plan({ content: 'Draft' });
  assertEquals(plan.operations.filter(op => op.entityType === 'task').length, 1);
  assertEquals(calls, ['read_pomodoist_mcp']);
  await assertRejects(() => create.plan({ content: '' }));
  assertEquals(calls.length, 1);
});
