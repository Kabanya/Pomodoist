import { readLimitedJson } from "./limited_json.ts";

export type Json = Record<string, unknown>;
export type CollaborationDependencies = {
  authenticate: (authorization: string) => Promise<string | null>;
  rpc: (authorization: string | null, request: Json) => Promise<Json>;
  upload: (path: string) => Promise<{ signedUrl: string; token: string }>;
  download: (path: string, name: string) => Promise<string>;
  cleanup: () => Promise<void>;
  inviteEmail: (email: string, url: string) => Promise<void>;
  webUrl: string;
};
export class CollaborationError extends Error {
  constructor(message: string, readonly code = "invalid_request", readonly status = 400) { super(message); }
}
const actions = new Set(["state", "share", "pull", "push", "invite", "accept", "members", "role", "remove", "leave", "transfer", "delete", "unshare", "publicLink", "publicRead", "notifications", "readNotification", "reserveUpload", "finishUpload", "deleteAttachment", "download", "export", "preferences"]);
const noScope = new Set(["state", "share", "accept", "publicRead", "notifications", "readNotification"]);
function required(map: Json, key: string, limit = 200): string {
  const value = map[key];
  if (typeof value !== "string" || !value.trim() || value.length > limit) throw new CollaborationError(`Invalid ${key}`);
  return value;
}
function integer(map: Json, key: string, max = Number.MAX_SAFE_INTEGER): number {
  const value = map[key];
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0 || value > max) throw new CollaborationError(`Invalid ${key}`);
  return value;
}
export function validateCollaborationRequest(value: unknown): Json {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new CollaborationError("Expected request object");
  const request = value as Json;
  const action = required(request, "action");
  if (!actions.has(action)) throw new CollaborationError("Unknown collaboration action");
  if (!noScope.has(action)) required(request, "scopeId");
  if (["accept", "publicRead"].includes(action)) required(request, "token", 128);
  if (action === "share") { required(request, "rootProjectId"); integer(request, "expectedRevision"); }
  if (["role", "remove", "transfer"].includes(action)) required(request, "userId");
  if (action === "readNotification") required(request, "notificationId");
  if (["download", "deleteAttachment"].includes(action)) required(request, "attachmentId");
  if (action === "finishUpload") required(request, "uploadId");
  if (["pull", "export"].includes(action) && request.sinceRevision !== undefined) integer(request, "sinceRevision");
  if (action === "publicLink" && typeof request.enabled !== "boolean") throw new CollaborationError("Invalid enabled");
  if (action === "role" && !["administrator", "member", "observer"].includes(String(request.role))) throw new CollaborationError("Invalid role");
  if (action === "invite") {
    if (request.revoke === true) required(request, "invitationId");
    else {
      if (request.role !== undefined && !["member", "observer"].includes(String(request.role))) throw new CollaborationError("Invalid invitation role");
      if (request.email !== undefined && request.email !== null && (typeof request.email !== "string" || request.email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(request.email))) throw new CollaborationError("Invalid invitation email");
    }
  }
  if (action === "preferences") {
    required(request, "entityType"); required(request, "entityId");
    if (!request.data || typeof request.data !== "object" || Array.isArray(request.data)) throw new CollaborationError("Invalid preference data");
  }
  if (action === "reserveUpload") {
    for (const key of ["taskId", "uploadId", "contentType"]) required(request, key);
    required(request, "name", 255);
    if (!integer(request, "bytes", 20_000_000)) throw new CollaborationError("Empty attachment");
  }
  if (action === "push") {
    if (!Array.isArray(request.operations) || request.operations.length > 200) throw new CollaborationError("Expected at most 200 operations");
    for (const raw of request.operations) {
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new CollaborationError("Invalid operation");
      const op = raw as Json;
      for (const key of ["opId", "entityType", "entityId"]) required(op, key);
      integer(op, "baseRevision");
      if (!["upsert", "delete", "assign"].includes(String(op.operation)) || !op.payload || typeof op.payload !== "object" || Array.isArray(op.payload) || !Number.isFinite(Date.parse(required(op, "clientUpdatedAt")))) throw new CollaborationError("Invalid operation");
    }
  }
  return request;
}

export function publicCollaborationProjection(result: Json): Json {
  const entities = Array.isArray(result.entities) ? result.entities as Json[] : [];
  const fields = new Set(["name", "content", "description", "parentId", "projectId", "taskId", "body", "dueJson", "deadlineJson", "status", "priority", "orderKey", "createdAt", "updatedAt", "completedAt", "creatorName", "assigneeNames"]);
  const ofType = (type: string) => entities.filter(e => e.entityType === type).map(e => ({
    ...Object.fromEntries(Object.entries((e.data ?? {}) as Json).filter(([key]) => fields.has(key))), id: e.id,
  }));
  return { scope: { id: result.scopeId, rootProjectId: result.rootProjectId }, projects: ofType("project"), tasks: ofType("task"), comments: ofType("comment") };
}

export async function handleCollaboration(request: Request, deps: CollaborationDependencies): Promise<Response> {
  const headers = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info", "Access-Control-Allow-Methods": "POST, OPTIONS", "Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow", "Content-Type": "application/json" };
  const reply = (data: Json, status = 200) => new Response(JSON.stringify(data), { status, headers });
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return reply({ error: "POST required", code: "method_not_allowed" }, 405);
  try {
    const parsed = await readLimitedJson(request, 1_000_000);
    if (!parsed.ok) return reply({ error: parsed.error, code: "invalid_request" }, parsed.status);
    const input = validateCollaborationRequest(parsed.value);
    const action = String(input.action);
    const authorization = request.headers.get("Authorization");
    if (action !== "publicRead" && (!authorization?.startsWith("Bearer ") || !await deps.authenticate(authorization))) throw new CollaborationError("Authentication required", "unauthenticated", 401);
    const result = await deps.rpc(action === "publicRead" ? null : authorization, input);
    if (action === "publicLink") return reply({ token: result.token, url: result.token ? `${deps.webUrl.replace(/\/$/, "")}/shared/public/${encodeURIComponent(String(result.token))}` : null });
    if (action === "invite" && result.token) {
      const url = `${deps.webUrl.replace(/\/$/, "")}/shared/join/${encodeURIComponent(String(result.token))}`;
      let emailDelivery = "not_requested";
      if (result.email) {
        try { await deps.inviteEmail(String(result.email), url); emailDelivery = "sent"; }
        catch { emailDelivery = "failed"; }
      }
      return reply({ ...result, url, emailDelivery });
    }
    if (action === "reserveUpload") {
      const { objectPath, ...safe } = result;
      return reply({ ...safe, path: objectPath, ...(!result.finished ? await deps.upload(String(objectPath)) : {}) });
    }
    if (action === "download") {
      const { objectPath, ...safe } = result;
      return reply({ ...safe, url: await deps.download(String(objectPath), String(result.name)) });
    }
    if (action === "publicRead") {
      return reply(publicCollaborationProjection(result));
    }
    // Cleanup is best effort after authorization; durable SQL records retry the work.
    if (["deleteAttachment", "delete", "unshare", "state", "finishUpload"].includes(action)) { try { await deps.cleanup(); } catch { /* Retained in the SQL deletion queue. */ } }
    const { objectPath: _path, ...safe } = result;
    return reply(safe);
  } catch (error) {
    if (error instanceof CollaborationError) return reply({ error: error.message, code: error.code }, error.status);
    return reply({ error: "Collaboration service is unavailable", code: "unavailable" }, 503);
  }
}
