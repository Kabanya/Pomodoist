import { spawnSync } from 'node:child_process';

const readTools = [
  'list_habits', 'get_habit', 'list_tasks', 'get_task', 'list_projects', 'list_labels', 'get_kanban_board',
  'list_focus_history', 'get_productivity_report', 'get_achievements',
  'openclaw_get_focus', 'openclaw_get_task',
  'openclaw_list_app_devices', 'openclaw_get_app_settings', 'openclaw_get_app_settings_request',
];
const writeTools = [
  'create_habit', 'update_habit', 'add_habit_check_in', 'complete_habit', 'undo_habit_check_in', 'finish_habit', 'reopen_habit', 'delete_habit',
  'create_task', 'update_task', 'complete_task', 'restore_task', 'delete_task',
  'create_project', 'update_project', 'delete_project', 'create_label', 'delete_label',
  'focus', 'set_task_details', 'set_app_shortcut', 'set_app_appearance',
].map(name => `openclaw_${name}`);

/** Generate one server definition, without reading or writing credentials. */
export function buildConfig(endpoint, mode = 'read') {
  if (!['read', 'write'].includes(mode)) throw new Error('Mode must be read or write.');
  let url;
  try { url = new URL(endpoint); } catch { throw new Error('A valid MCP endpoint is required.'); }
  const rawHost = /^https?:\/\/(\[[^\]]+\]|[^/:?#]+)(?::\d+)?(?:\/|$)/i.exec(endpoint)?.[1];
  if (typeof endpoint !== 'string' || /\s|\\/.test(endpoint) ||
      url.username || url.password || url.search || url.hash ||
      !['https:', 'http:'].includes(url.protocol) ||
      (url.protocol === 'http:' && !['localhost', '127.0.0.1', '[::1]'].includes(rawHost))) {
    throw new Error('Use HTTPS (or exact loopback HTTP), without credentials, query, or fragment.');
  }
  return {
    url: url.href, transport: 'streamable-http', enabled: true, auth: 'oauth',
    sslVerify: true, connectionTimeoutMs: 10000, requestTimeoutMs: 45000,
    supportsParallelToolCalls: false,
    toolFilter: { include: [...readTools, ...(mode === 'write' ? writeTools : [])] },
  };
}

export function connectionCommands(endpoint, mode = 'read') {
  return [
    ['mcp', 'set', 'pomodoist', JSON.stringify(buildConfig(endpoint, mode))],
    ['mcp', 'login', 'pomodoist'],
    ['mcp', 'doctor', 'pomodoist', '--probe'],
  ];
}

function inspectCli(args, message) {
  const result = spawnSync('openclaw', args, {
    encoding: 'utf8', shell: false, timeout: 30000, maxBuffer: 4 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) throw new Error(message);
  return result.stdout;
}

function preflight(config) {
  const upgrade = 'OpenClaw native MCP OAuth is required. Upgrade to OpenClaw 2026.9.3 or newer, then retry.';
  const help = inspectCli(['mcp', '--help'], upgrade);
  for (const command of ['list', 'set', 'login', 'doctor', 'logout', 'unset']) {
    if (!new RegExp(`^\\s+${command}(?=\\s|\\[|$)`, 'm').test(help)) throw new Error(upgrade);
  }
  if (!inspectCli(['mcp', 'doctor', '--help'], upgrade).includes('--probe')) throw new Error(upgrade);
  const inspectError = 'Cannot inspect saved MCP servers. Check openclaw mcp list --json before retrying.';
  let servers;
  try { servers = JSON.parse(inspectCli(['mcp', 'list', '--json'], inspectError)); }
  catch { throw new Error(inspectError); }
  if (!servers || typeof servers !== 'object' || Array.isArray(servers)) throw new Error(inspectError);
  if (Object.hasOwn(servers, 'pomodoist')) {
    const existing = servers.pomodoist;
    let sameEndpoint = false;
    try { sameEndpoint = !existing.command && new URL(existing.url).href === config.url; } catch { /* Refuse unknown definitions. */ }
    if (!sameEndpoint) {
      throw new Error('A different pomodoist server is already configured. Revoke the old connection in Pomodoist Settings, then run openclaw mcp logout pomodoist and openclaw mcp unset pomodoist before switching servers.');
    }
  }
}

export function runCli(argv = process.argv.slice(2)) {
  try {
    const [endpoint, ...flags] = argv;
    if (!endpoint || flags.some(flag => !['--write', '--apply'].includes(flag))) {
      throw new Error('Usage: node scripts/configure.mjs <MCP_URL> [--write] [--apply]');
    }
    const mode = flags.includes('--write') ? 'write' : 'read';
    const config = buildConfig(endpoint, mode);
    if (!flags.includes('--apply')) {
      console.log(JSON.stringify({ mcp: { servers: { pomodoist: config } } }, null, 2));
    } else {
      preflight(config);
      for (const args of connectionCommands(endpoint, mode)) {
        const result = spawnSync('openclaw', args, { stdio: 'inherit', shell: false });
        if (result.error || result.status !== 0) {
          throw new Error(`OpenClaw mcp ${args[1]} failed; setup stopped. Check the command output and retry after resolving the error.`);
        }
      }
      console.log('Connected. Restart the running OpenClaw gateway/agent to load the new definition.');
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}

if (import.meta.main) runCli();
