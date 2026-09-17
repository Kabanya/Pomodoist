import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { CollaborationError, type CollaborationDependencies, handleCollaboration } from "../_shared/pomodoist_collaboration.ts";
import { collaborationRuntime } from "../_shared/pomodoist_collaboration_runtime.ts";
import { type PomodoistMcpAuth, type PomodoistMcpConfig, type PomodoistMcpFetch, toolError, toolSuccess } from "./pomodoist_mcp.ts";

type Dependencies = {
  config: PomodoistMcpConfig;
  fetch?: PomodoistMcpFetch;
  webUrl?: string;
  publicUrl?: string;
  collaboration?: Partial<CollaborationDependencies>;
};
const actions = ["state", "share", "pull", "push", "invite", "accept", "members", "role", "remove", "leave", "transfer", "delete", "unshare", "publicLink", "publicRead", "notifications", "readNotification", "reserveUpload", "finishUpload", "deleteAttachment", "download", "export", "preferences"] as const;

export function registerCollaborationTool(server: McpServer, auth: PomodoistMcpAuth, dependencies: Dependencies, outputSchema: z.ZodType) {
  server.registerTool("shared_projects", {
    description: "Shared project collaboration. Start with state to obtain scopes, invitations, personalRevision and history policy. Pass action arguments in arguments: share(rootProjectId); pull/export(scopeId,sinceRevision) return paginated entities/members/preferences; push(scopeId,operations[{opId,entityType,entityId,operation,payload,baseRevision,clientUpdatedAt}]) edits tasks/projects/comments or assigns tasks with operation=assign,payload={add:[],remove:[]}. Use accepted editor user IDs for assignees/mentions. invite(scopeId,email?,role=member|observer), accept(token), members(scopeId), role/remove/transfer(scopeId,userId,role?), leave/delete(scopeId), unshare(scopeId) stops sharing and restores the owner's private project, publicLink(scopeId,enabled), publicRead(token), notifications, readNotification(notificationId), preferences(scopeId,entityType,entityId,data). Files: reserveUpload(scopeId,taskId,uploadId,name,contentType,bytes), PUT bytes to returned signedUrl, finishUpload(scopeId,uploadId), download/deleteAttachment(scopeId,attachmentId). Downloads are private; export includes task/comment/author/assignee/focus/file records. Ordinary task tools address personal data; this tool addresses shared scopes.",
    inputSchema: z.object({ action: z.enum(actions), arguments: z.record(z.string(), z.unknown()).default({}) }).strict(),
    outputSchema,
    annotations: { openWorldHint: true, destructiveHint: true, readOnlyHint: false },
  }, async ({ action, arguments: arguments_ }) => {
    try { return toolSuccess(await callCollaboration(auth, dependencies, { ...arguments_, action })); }
    catch (error) {
      if (error instanceof CollaborationError) return toolError(error.status === 403 || error.status === 401 ? "forbidden" : error.status === 409 ? "conflict" : error.status === 429 ? "rate_limited" : error.status < 500 ? "invalid_argument" : "internal", error.message);
      return toolError("internal", "Collaboration service is unavailable.");
    }
  });
}

export async function callCollaboration(auth: PomodoistMcpAuth, dependencies: Dependencies, request: Record<string, unknown>) {
  const fetcher = dependencies.fetch ?? fetch;
  const rpc: CollaborationDependencies["rpc"] = async (_, input) => {
    const response = await fetcher(`${dependencies.config.supabaseUrl.replace(/\/+$/, "")}/rest/v1/rpc/pomodoist_collaboration_mcp`, {
      method: "POST", signal: AbortSignal.timeout(20000),
      headers: { apikey: dependencies.config.serviceRoleKey, Authorization: `Bearer ${dependencies.config.serviceRoleKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({ p_subject: auth.subject, p_session_id: auth.sessionId, p_client_id: auth.clientId, p_request: input }),
    });
    const data = await response.json();
    if (!response.ok) throw new CollaborationError(typeof data.message === "string" ? data.message : "Collaboration request failed", String(data.code ?? "unavailable"), response.status);
    return data;
  };
  const runtime = collaborationRuntime({ url: dependencies.config.supabaseUrl, publicUrl: dependencies.publicUrl, key: dependencies.config.serviceRoleKey,
    webUrl: dependencies.webUrl ?? "https://app.pomodoist.com", env: Deno.env, fetcher,
    authenticate: async () => auth.userId, rpc });
  const deps = { ...runtime, ...dependencies.collaboration };
  // Resolve the current personal revision before transferring an online MCP project.
  const input = { ...request };
  if (input.action === "share" && input.expectedRevision === undefined) {
    input.expectedRevision = (await deps.rpc(null, { action: "state" })).personalRevision;
  }
  const response = await handleCollaboration(new Request("https://collaboration.invalid", {
    method: "POST", headers: { Authorization: "Bearer resolved-mcp-session", "Content-Type": "application/json" }, body: JSON.stringify(input),
  }), deps);
  const result = await response.json();
  if (!response.ok) throw new CollaborationError(result.error, result.code, response.status);
  return result as Record<string, unknown>;
}
