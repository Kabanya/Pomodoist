import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { type PomodoistMcpAuth, toolSuccess } from './pomodoist_mcp.ts';
import { type PomodoistToolDependencies, outputEnvelope, record, rpc, safe } from './tool_core.ts';

const uuid = z.string().uuid();
const version = z.string().min(1).max(128);
const appearanceSettings = ['themeMode', 'theme', 'customTheme', 'icon', 'statusItemStyle', 'bottomNavigation', 'taskDetailLayout', 'taskListStyle', 'taskBranchStyle', 'taskRowSpacing', 'taskTimeDisplayMode', 'zoom', 'focusTimerStyle', 'focusViewMode'] as const;
const command = z.enum(['toggleSidebar', 'togglePomo', 'toggleTaskDetails', 'toggleTaskDetailsAlternate', 'quickAdd', 'browse', 'search', 'today', 'upcoming', 'focus', 'focusAlternate', 'inbox', 'priorityMatrix', 'calendar', 'timeline', 'kanban', 'reports', 'settings', 'globalQuickAdd']);
const modifiers = { keyLabel: z.string().min(1).max(64), meta: z.boolean().optional(), control: z.boolean().optional(), alt: z.boolean().optional(), shift: z.boolean().optional() };
const binding = z.union([z.object({ physicalKeyId: z.number().int().positive().max(Number.MAX_SAFE_INTEGER), ...modifiers }).strict(), z.object({ keyCode: z.number().int().nonnegative().max(65535), ...modifiers }).strict()]).nullable();
const shortcutValue = z.object({ command, binding, enabled: z.boolean().optional() }).strict();
const hex = z.string().regex(/^#[0-9a-fA-F]{6}$/);
const image = z.object({ imageId: z.string().max(128).nullable().optional(), dim: z.number().min(0).max(1).optional(), blur: z.number().min(0).max(20).optional() }).strict();
const customTheme = z.object({ light: z.record(z.string().max(64), hex).optional(), dark: z.record(z.string().max(64), hex).optional(),
  backgrounds: z.object({ type: z.enum(['color', 'photo', 'macosGlass']).optional(), mode: z.enum(['mainOnly', 'wholeApp', 'separate']).optional(),
    glassLightDim: z.number().min(0).max(1).optional(), glassDarkDim: z.number().min(0).max(1).optional(), images: z.record(z.string().max(64), image).optional() }).strict().optional(),
  image_url: z.string().url().max(2048).refine(value => { const url = new URL(value); return url.protocol === 'https:' && !url.username && !url.password; }).optional(),
  image_palette: z.enum(['light', 'dark']).optional(), image_zone: z.enum(['main', 'sidebar', 'quickAdd']).optional(),
}).strict();
const navigation = z.object({ style: z.enum(['soft', 'labels']), destinations: z.array(z.enum(['today', 'upcoming', 'focus', 'inbox', 'projects', 'browse', 'search', 'calendar', 'timeline', 'kanban', 'priorityMatrix', 'reports', 'habits', 'settings'])).max(5).refine(items => new Set(items).size === items.length) }).strict();
const appearanceValue = z.union([z.string().max(128), z.number().finite(), z.boolean(), customTheme, navigation]);
const writeBase = { request_id: uuid, device_id: uuid, expected_version: version };
const outputSchema = outputEnvelope(z.record(z.string(), z.unknown()));

export function registerAppSettingsTools(server: McpServer, auth: PomodoistMcpAuth, dependencies: PomodoistToolDependencies, prefix = '') {
  const fetcher = dependencies.fetch ?? fetch;
  const context = { auth, config: dependencies.config, fetcher: (input: RequestInfo | URL, init?: RequestInit) => fetcher(input, { ...init, signal: AbortSignal.timeout(5000) }), log: dependencies.log ?? (() => {}) };
  async function call(command: Record<string, unknown>) {
    return record(await rpc(context, 'pomodoist_app_settings_agent', { p_subject: auth.subject, p_session_id: auth.sessionId, p_client_id: auth.clientId, p_command: command })) ?? {};
  }
  async function request(command: Record<string, unknown>, wait: number) {
    const end = Date.now() + wait;
    let result = await call({ ...command, action: 'request' });
    while (['pending', 'claimed'].includes(String(result.status)) && Date.now() < end) {
      await new Promise(resolve => setTimeout(resolve, Math.min(250, end - Date.now())));
      result = await call({ action: 'status', request_id: command.request_id });
    }
    return toolSuccess(result);
  }
  function register(name: string, inputSchema: z.ZodType, readOnly: boolean, description: string, run: (args: any) => Promise<ReturnType<typeof toolSuccess>>) {
    server.registerTool(`${prefix}${name}`, { inputSchema, outputSchema, description,
      annotations: { readOnlyHint: readOnly, idempotentHint: true, openWorldHint: false, destructiveHint: false } }, safe(run));
  }
  register('list_app_devices', z.object({}).strict(), true, 'List registered Pomodoist devices with online availability, lease expiry and supported settings. Select an explicit online device for fresh reads or changes.', async () => toolSuccess(await call({ action: 'list' })));
  register('get_app_settings', z.object({ device_id: uuid }).strict(), true, 'Request a fresh settings snapshot from this online device. Includes values, versions and capabilities; pending returns request_id for status polling.', args => request({ ...args, request_id: crypto.randomUUID(), operation: 'read' }, 15000));
  register('set_app_shortcut', z.object({ ...writeBase, value: shortcutValue }).strict(), false, 'Set one shortcut on the selected online device. Read settings first; expected_version is the shortcuts version. binding:null resets. Internal bindings use physicalKeyId; globalQuickAdd uses the current OS native keyCode shown in the snapshot. Reuse request_id and identical arguments after timeouts; never blindly retry uncertain outcomes.', args => request({ ...args, operation: 'shortcut', setting: 'shortcuts' }, 1000));
  register('set_app_appearance', z.object({ ...writeBase, setting: z.enum(appearanceSettings), value: appearanceValue }).strict(), false, 'Set one appearance group using its fresh expected_version. customTheme accepts partial light/dark role colors, backgrounds, or a public HTTPS image_url with image_palette/image_zone. Settings stay local to this device. Reuse request_id and identical arguments after timeouts; never blindly retry uncertain outcomes.', args => request({ ...args, operation: 'appearance' }, 1000));
  register('get_app_settings_request', z.object({ request_id: uuid }).strict(), true, 'Read a settings request receipt. expired means it was not claimed; uncertain means it may have applied: read fresh device settings before deciding.', async args => toolSuccess(await call({ ...args, action: 'status' })));
}
