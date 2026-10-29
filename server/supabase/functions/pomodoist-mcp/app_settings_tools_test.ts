import { assert, assertEquals } from '@std/assert';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { registerAppSettingsTools } from './app_settings_tools.ts';
const uuid = '11111111-1111-4111-8111-111111111111';
function fixture(devices: unknown[] = []) {
  const tools = new Map<string, { schema: z.ZodType; run: (args: any) => Promise<any> }>();
  const calls: any[] = [];
  registerAppSettingsTools({ registerTool(name: string, config: any, run: any) {
    tools.set(name, { schema: config.inputSchema, run });
  } } as unknown as McpServer, { subject: uuid, userId: uuid, sessionId: uuid, clientId: uuid }, {
    config: { issuer: 'https://example.com/auth/v1', resourceUrl: 'https://example.com/mcp', allowedOrigins: [], supabaseUrl: 'https://example.com', serviceRoleKey: 'test' },
    fetch: async (url, init) => { calls.push({ url: String(url), ...JSON.parse(String(init?.body)) });
      const command = calls.at(-1).p_command;
      return Response.json(command.action === 'list' ? { devices } : { request_id: command.request_id, status: 'applied', result: { status: 'applied', values: {} } }); },
  });
  return { tools, calls, invoke: (name: string, args: unknown) => { const tool = tools.get(name)!; return tool.run(tool.schema.parse(args)); } };
}
Deno.test('settings tools use their session-bound receipt gateway and fresh read request', async () => {
  const { calls, invoke } = fixture();
  await invoke('get_app_settings', { device_id: uuid });
  assertEquals(calls[0].p_command.operation, 'read');
  assertEquals(calls[0].p_command.action, 'request');
  assert(z.string().uuid().safeParse(calls[0].p_command.request_id).success);
  assertEquals(calls[0].p_session_id, uuid);
  assert(calls[0].url.endsWith('/pomodoist_app_settings_agent'));
});
Deno.test('write schema requires UUID and expected version; forwards valid custom theme shape', async () => {
  const { calls, invoke, tools } = fixture();
  const input = { request_id: uuid, device_id: uuid, setting: 'customTheme', value: { light: { primary: '#112233' }, backgrounds: { type: 'photo', images: { 'main.light': { imageId: null, dim: 0.4 } } }, image_url: 'https://example.com/a.png', image_palette: 'light', image_zone: 'main' }, expected_version: 'v1' };
  await invoke('set_app_appearance', input);
  assertEquals(calls[0].p_command.value, input.value);
  assertEquals(calls[0].p_command.request_id, uuid);
  assert(!tools.get('set_app_appearance')!.schema.safeParse({ ...input, request_id: 'bad' }).success);
  assert(!tools.get('set_app_appearance')!.schema.safeParse({ ...input, expected_version: undefined }).success);
  assert(!tools.get('set_app_appearance')!.schema.safeParse({ ...input, setting: 'billing' }).success);
});
Deno.test('shortcut group retains reset and global enabled shape', async () => {
  const { calls, invoke } = fixture();
  await invoke('set_app_shortcut', { request_id: uuid, device_id: uuid, value: { command: 'globalQuickAdd', binding: null, enabled: false }, expected_version: 'v1' });
  assertEquals(calls[0].p_command.setting, 'shortcuts');
  assertEquals(calls[0].p_command.value, { command: 'globalQuickAdd', binding: null, enabled: false });
});
Deno.test('OpenClaw names retain identical UUID settings gateway without task mutation wrapper', async () => {
  const tools: string[] = [];
  registerAppSettingsTools({ registerTool(name: string) { tools.push(name); } } as unknown as McpServer, { subject: uuid, userId: uuid, sessionId: uuid, clientId: uuid }, { config: {} as any }, 'openclaw_');
  assertEquals(tools, ['openclaw_list_app_devices','openclaw_get_app_settings','openclaw_set_app_shortcut','openclaw_set_app_appearance','openclaw_get_app_settings_request']);
});

Deno.test('appearance schema accepts every adapter group including bottom navigation', async () => {
  const { calls, invoke } = fixture();
  for (const [setting, value] of Object.entries({ themeMode: 'dark', theme: 'custom', customTheme: { dark: { primary: '#123456' } }, icon: 'classic', statusItemStyle: 'classic', bottomNavigation: { style: 'soft', destinations: ['today', 'focus'] }, taskDetailLayout: 'panel', taskListStyle: 'compact', taskBranchStyle: 'lines', taskRowSpacing: 'comfortable', taskTimeDisplayMode: 'estimate', zoom: 1.1, focusTimerStyle: 'classic', focusViewMode: 'timer' })) {
    await invoke('set_app_appearance', { request_id: uuid, device_id: uuid, expected_version: 'v1', setting, value });
    assertEquals(calls.at(-1).p_command.value, value);
  }
});

Deno.test('pending writes recheck the same session and UUID through status', async () => {
  const commands: any[] = [];
  const tools = new Map<string, (args: any) => Promise<any>>();
  registerAppSettingsTools({ registerTool(name: string, _: unknown, run: any) { tools.set(name, run); } } as unknown as McpServer, { subject: uuid, userId: uuid, sessionId: uuid, clientId: uuid }, {
    config: { issuer: 'https://example.com/auth/v1', resourceUrl: 'https://example.com/mcp', allowedOrigins: [], supabaseUrl: 'https://example.com', serviceRoleKey: 'test' },
    fetch: async (_, init) => { const body = JSON.parse(String(init?.body)); commands.push(body); return Response.json({ request_id: uuid, status: body.p_command.action === 'request' ? 'pending' : 'applied' }); },
  });
  const result = await tools.get('set_app_appearance')!({ request_id: uuid, device_id: uuid, setting: 'zoom', value: 1, expected_version: 'v1' });
  assertEquals(result.structuredContent.data.status, 'applied');
  assertEquals(commands.map(body => body.p_command.action), ['request', 'status']);
  assertEquals(commands[1].p_command.request_id, uuid);
  assertEquals(commands[1].p_session_id, uuid);
});

Deno.test('device listing preserves explicit online and offline availability', async () => {
  const devices = [{ device_id: uuid, name: 'Mac', online: false, lease_until: '2026-10-29T00:00:00Z', capabilities: {} }];
  const { invoke, calls } = fixture(devices);
  const result = await invoke('list_app_devices', {});
  assertEquals(result.structuredContent.data.devices, devices);
  assertEquals(calls[0].p_command, { action: 'list' });
});
