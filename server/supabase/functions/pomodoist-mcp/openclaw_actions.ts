// Runtime-independent action planning. Only the commit RPC may persist writes.
export type JsonMap = Record<string, unknown>;
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
