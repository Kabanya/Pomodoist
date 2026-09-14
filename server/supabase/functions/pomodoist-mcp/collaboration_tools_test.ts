import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { callCollaboration } from "./collaboration_tools.ts";
const auth = { subject: "subject", userId: "resolved-user", sessionId: "session", clientId: "client" };
const config = { issuer: "https://api.test", resourceUrl: "https://api.test/mcp", allowedOrigins: [], supabaseUrl: "https://api.test", serviceRoleKey: "test-service-key" };
Deno.test("shared MCP binds the validated session and never accepts a user override", async () => {
  const calls: Record<string, unknown>[] = [];
  const result = await callCollaboration(auth, { config, fetch: async (_, init) => {
    calls.push(JSON.parse(String(init?.body))); return Response.json({ scopes: [], personalRevision: 9 });
  }, collaboration: { cleanup: async () => {} } }, { action: "state", userId: "attacker" });
  assertEquals(result.personalRevision, 9);
  assertEquals(calls[0].p_subject, "subject"); assertEquals(calls[0].p_session_id, "session");
  assertEquals(calls[0].p_client_id, "client"); assertEquals(calls[0].p_user_id, undefined);
});
Deno.test("MCP sharing obtains a current personal revision before transfer", async () => {
  const actions: Record<string, unknown>[] = [];
  await callCollaboration(auth, { config, fetch: async (_, init) => {
    const input = JSON.parse(String(init?.body)).p_request; actions.push(input);
    return Response.json(input.action === "state" ? { personalRevision: 17 } : { scope: { id: "shared" } });
  } }, { action: "share", rootProjectId: "root" });
  assertEquals(actions, [{ action: "state" }, { action: "share", rootProjectId: "root", expectedRevision: 17 }]);
});
Deno.test("revoked MCP scope cannot reach file signing", async () => {
  let signed = false;
  await assertRejects(() => callCollaboration(auth, { config,
    fetch: async () => Response.json({ code: "42501", message: "Shared scope inaccessible" }, { status: 403 }),
    collaboration: { download: async () => { signed = true; return "never"; } },
  }, { action: "download", scopeId: "scope", attachmentId: "file" }));
  assertEquals(signed, false);
});
Deno.test("MCP invitations reuse the email boundary after authorized SQL acceptance", async () => {
  const messages: string[] = [];
  const result = await callCollaboration(auth, { config, webUrl: "https://app.test",
    fetch: async () => Response.json({ token: "invite-token", email: "invitee@test.example" }),
    collaboration: { inviteEmail: async (email, url) => { messages.push(`${email} ${url}`); } },
  }, { action: "invite", scopeId: "scope", email: "invitee@test.example", role: "observer" });
  assertEquals(result.emailDelivery, "sent");
  assertEquals(messages, ["invitee@test.example https://app.test/shared/join/invite-token"]);
});
