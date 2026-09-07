// Runtime-independent action planning. Only the commit RPC may persist writes.
export type JsonMap = Record<string, unknown>;
export type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>;
export type Plan = { operations: JsonMap[]; result: JsonMap };
export type Identity = { subject: string; sessionId: string; clientId: string };
export class ActionError extends Error {
  code: string;
  constructor(code: string, message: string) { super(message); this.code = code; }
}

export function canonicalJson(value: unknown): string {
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return JSON.stringify(value);
  if (typeof value === 'number' && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`;
  if (value && typeof value === 'object' && Object.getPrototypeOf(value) === Object.prototype) {
    const record = value as JsonMap;
    return `{${Object.keys(record).sort().map(key => `${JSON.stringify(key)}:${canonicalJson(record[key])}`).join(',')}}`;
  }
  throw new ActionError('invalid_argument', 'Arguments must be finite JSON values.');
}

export async function runGuardedAction(
  identity: Identity,
  action: { requestId: string; name: string; arguments: unknown },
  rpc: (arguments_: JsonMap) => Promise<JsonMap>,
  build: () => Promise<Plan>,
): Promise<JsonMap> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(canonicalJson(action.arguments)));
  const args = {
    p_subject: identity.subject, p_session_id: identity.sessionId, p_client_id: identity.clientId,
    p_request_id: action.requestId, p_action: action.name,
    p_arguments_hash: Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, '0')).join(''),
  };
  const prepared = await rpc(args);
  if (prepared.result != null) return prepared.result as JsonMap;
  if (typeof prepared.revision !== 'string' || !/^\d+$/.test(prepared.revision)) {
    throw new ActionError('internal', 'Invalid action revision.');
  }
  const plan = await build();
  if (!plan.operations.length) throw new ActionError('conflict', 'Action has no effect.');
  return await rpc({ ...args, p_expected_revision: prepared.revision, p_operations: plan.operations, p_result: plan.result });
}

export async function captureMutation(
  supabaseUrl: string,
  upstream: Fetcher,
  run: (fetcher: Fetcher) => Promise<unknown>,
): Promise<Plan> {
  const base = `${supabaseUrl.replace(/\/+$/, '')}/rest/v1/rpc/`;
  let operations: JsonMap[] | undefined;
  const fetcher: Fetcher = async (input, init) => {
    const request = new Request(input, init);
    if (request.method !== 'POST') throw new ActionError('internal', 'Unexpected mutation transport.');
    if (request.url === `${base}read_pomodoist_mcp`) return await upstream(input, init);
    if (request.url === `${base}send_pomodoist_mcp_sync_hint`) return Response.json(null);
    if (request.url !== `${base}push_pomodoist_mcp_changes` || operations !== undefined) {
      throw new ActionError('internal', 'Unexpected mutation transport.');
    }
    const body = await request.json();
    if (!Array.isArray(body.p_operations) || body.p_operations.length === 0) {
      throw new ActionError('internal', 'Mutation did not produce operations.');
    }
    operations = body.p_operations;
    return Response.json({ serverRevision: null });
  };
  const response = await run(fetcher) as { structuredContent?: JsonMap };
  const envelope = response?.structuredContent;
  if (envelope?.ok !== true) {
    const error = envelope?.error as JsonMap | undefined;
    throw new ActionError(String(error?.code ?? 'internal'), String(error?.message ?? 'Action failed.'));
  }
  if (!operations || !envelope.data || typeof envelope.data !== 'object' || Array.isArray(envelope.data)) {
    throw new ActionError('internal', 'Invalid action plan.');
  }
  return { operations, result: envelope.data as JsonMap };
}
