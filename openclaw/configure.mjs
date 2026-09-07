import { spawnSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const readTools = [
  'list_tasks', 'get_task', 'list_projects', 'list_labels', 'get_kanban_board',
  'list_focus_history', 'get_productivity_report', 'get_achievements',
  'openclaw_get_focus', 'openclaw_get_task',
];
const writeTools = [
  'create_task', 'update_task', 'complete_task', 'restore_task', 'delete_task',
  'create_project', 'update_project', 'delete_project', 'create_label', 'delete_label',
  'focus', 'set_task_details',
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

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const [endpoint, ...flags] = process.argv.slice(2);
    if (!endpoint || flags.some(flag => !['--write', '--apply'].includes(flag))) {
      throw new Error('Usage: node openclaw/configure.mjs <MCP_URL> [--write] [--apply]');
    }
    const mode = flags.includes('--write') ? 'write' : 'read';
    const config = buildConfig(endpoint, mode);
    if (!flags.includes('--apply')) {
      console.log(JSON.stringify({ mcp: { servers: { pomodoist: config } } }, null, 2));
    } else {
      for (const args of connectionCommands(endpoint, mode)) {
        const result = spawnSync('openclaw', args, { stdio: 'inherit', shell: false });
        if (result.error || result.status !== 0) {
          throw new Error('OpenClaw setup stopped. Check installation, OAuth consent, and MCP status.');
        }
      }
      console.log('Connected. Restart the running OpenClaw gateway/agent to load the new definition.');
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
