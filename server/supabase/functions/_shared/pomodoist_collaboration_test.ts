import { CollaborationError, handleCollaboration, publicCollaborationProjection, validateCollaborationRequest, type CollaborationDependencies } from "./pomodoist_collaboration.ts";
import { sendInvitationEmail, type SmtpConnection } from "./pomodoist_collaboration_mail.ts";
function equal(actual: unknown, expected: unknown) { if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`Expected ${JSON.stringify(expected)}, received ${JSON.stringify(actual)}`); }
function rejects(fn: () => unknown) { try { fn(); } catch { return; } throw new Error("Expected rejection"); }
function fixture(result: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const deps: CollaborationDependencies = {
    authenticate: async () => { calls.push("auth"); return "actor"; },
    rpc: async (_auth, input) => { calls.push(`rpc:${input.action}`); return result; },
    upload: async path => { calls.push(`upload:${path}`); return { signedUrl: "https://storage/upload", token: "signed" }; },
    download: async path => { calls.push(`download:${path}`); return "https://storage/download"; },
    cleanup: async () => { calls.push("cleanup"); },
    inviteEmail: async email => { calls.push(`email:${email}`); },
    webUrl: "https://app.example.com",
  };
  const request = (input: unknown, auth = true) => new Request("https://edge.example.com", { method: "POST", headers: auth ? { Authorization: "Bearer user-jwt" } : {}, body: JSON.stringify(input) });
  return { calls, deps, request };
}
Deno.test("request boundary rejects malformed batch, missing revisions and header injection", () => {
  for (const value of [null, [], { action: "unknown" }, { action: "share", rootProjectId: "x" }, { action: "publicLink", scopeId: "s", enabled: "true" },
    { action: "reserveUpload", scopeId: "s", taskId: "t", uploadId: "u", name: "f", contentType: "image/png", bytes: 20_000_001 },
    { action: "invite", scopeId: "s", email: "a@b.com\r\nBcc: other@b.com" }, { action: "invite", scopeId: "s", role: "administrator" },
    { action: "push", scopeId: "s", operations: [{ opId: "o", entityId: "t", entityType: "task", operation: "upsert", payload: {}, clientUpdatedAt: "2026-09-14" }] },
  ]) rejects(() => validateCollaborationRequest(value));
});
Deno.test("all documented actions accept their minimal valid shapes", () => {
  const values = [
    { action: "state" }, { action: "share", rootProjectId: "p", expectedRevision: 0 }, { action: "publicRead", token: "token" }, { action: "accept", token: "token" },
    { action: "pull", scopeId: "s", sinceRevision: 0 }, { action: "export", scopeId: "s", sinceRevision: 0 },
    { action: "push", scopeId: "s", operations: [{ opId: "o", entityType: "task", entityId: "t", operation: "assign", payload: { add: ["u"], remove: [] }, baseRevision: 1, clientUpdatedAt: "2026-09-14T00:00:00Z" }] },
    ...["invite", "members", "leave", "delete"].map(action => ({ action, scopeId: "s" })),
    ...["role", "remove", "transfer"].map(action => ({ action, scopeId: "s", userId: "u", role: "member" })),
    { action: "publicLink", scopeId: "s", enabled: false }, { action: "notifications" }, { action: "readNotification", notificationId: "n" },
    { action: "reserveUpload", scopeId: "s", taskId: "t", uploadId: "u", name: "file", contentType: "text/plain", bytes: 20_000_000 },
    { action: "finishUpload", scopeId: "s", uploadId: "u" }, ...["deleteAttachment", "download"].map(action => ({ action, scopeId: "s", attachmentId: "a" })),
  ];
  for (const value of values) equal(validateCollaborationRequest(value), value);
});
Deno.test("unauthenticated private operations never reach SQL, Storage or email", async () => {
  const f = fixture(); const response = await handleCollaboration(f.request({ action: "state" }, false), f.deps);
  equal(response.status, 401); equal(f.calls, []);
});
Deno.test("revoked access from SQL prevents service-role signing", async () => {
  const f = fixture(); f.deps.rpc = async () => { throw new CollaborationError("Revoked", "42501", 403); };
  const response = await handleCollaboration(f.request({ action: "download", scopeId: "s", attachmentId: "a" }), f.deps);
  equal(response.status, 403); equal(f.calls, ["auth"]);
});
Deno.test("upload signing uses only the authorized SQL object path", async () => {
  const f = fixture({ uploadId: "u", objectPath: "s/actor/u", expiresAt: "later", finished: false });
  const response = await handleCollaboration(f.request({ action: "reserveUpload", scopeId: "s", taskId: "t", uploadId: "u", name: "f", contentType: "text/plain", bytes: 12, objectPath: "other-user/secret" }), f.deps);
  equal(f.calls, ["auth", "rpc:reserveUpload", "upload:s/actor/u"]);
  equal(await response.json(), { uploadId: "u", expiresAt: "later", finished: false, path: "s/actor/u", signedUrl: "https://storage/upload", token: "signed" });
});
Deno.test("finished upload replay does not issue another upload capability", async () => {
  const f = fixture({ uploadId: "u", objectPath: "s/actor/u", finished: true });
  await handleCollaboration(f.request({ action: "reserveUpload", scopeId: "s", taskId: "t", uploadId: "u", name: "f", contentType: "text/plain", bytes: 12 }), f.deps);
  equal(f.calls, ["auth", "rpc:reserveUpload"]);
});
Deno.test("public reads bypass user auth and remain non-indexable", async () => {
  const f = fixture({ scopeId: "s", rootProjectId: "p", entities: [{ id: "p", entityType: "project", data: { name: "Shared" } }] });
  const response = await handleCollaboration(f.request({ action: "publicRead", token: "token" }, false), f.deps);
  equal(f.calls, ["rpc:publicRead"]); equal(response.headers.get("X-Robots-Tag"), "noindex, nofollow");
  equal(await response.json(), { scope: { id: "s", rootProjectId: "p" }, projects: [{ name: "Shared", id: "p" }], tasks: [], comments: [] });
});
Deno.test("invitation SMTP failure preserves its reviewable token and reports failed delivery", async () => {
  const f = fixture({ id: "i", token: "token", email: "user@example.com" });
  f.deps.inviteEmail = async () => { throw new Error("smtp failed"); };
  const response = await handleCollaboration(f.request({ action: "invite", scopeId: "s", email: "user@example.com" }), f.deps);
  equal(response.status, 200); equal((await response.json()).emailDelivery, "failed");
});
Deno.test("only invitations send mail; cleanup failures preserve successful mutations", async () => {
  const f = fixture({ ok: true }); f.deps.cleanup = async () => { throw new Error("offline storage"); };
  const response = await handleCollaboration(f.request({ action: "delete", scopeId: "s" }), f.deps);
  equal(response.status, 200); equal(f.calls, ["auth", "rpc:delete"]);
});
Deno.test("successful owner unshare responds while storage cleanup is still pending", async () => {
  const f = fixture({ ok: true, restored: 1, rootProjectId: "project" });
  const cleanup = Promise.withResolvers<void>();
  const started = Promise.withResolvers<void>();
  const background: Promise<unknown>[] = [];
  f.deps.cleanup = () => { started.resolve(); return cleanup.promise; };
  f.deps.waitUntil = task => { background.push(task); };
  const response = handleCollaboration(f.request({ action: "unshare", scopeId: "scope" }), f.deps);
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    await started.promise;
    const result = await Promise.race([
      response,
      new Promise<null>(resolve => { timer = setTimeout(() => resolve(null), 100); }),
    ]);
    if (!result) throw new Error("Committed unshare is blocked on storage cleanup");
    equal(result.status, 200);
    equal(await result.json(), { ok: true, restored: 1, rootProjectId: "project" });
    equal(background.length, 1);
    cleanup.reject(new Error("Storage timed out after the mutation committed"));
    await Promise.all(background);
  } finally {
    clearTimeout(timer);
    cleanup.resolve();
    await response;
  }
});
Deno.test("oversized requests never authenticate", async () => {
  const f = fixture(); const response = await handleCollaboration(f.request({ action: "state", extra: "x".repeat(1_000_001) }), f.deps);
  equal(response.status, 413); equal(f.calls, []);
});
Deno.test("SMTP negotiates TLS before credentials and delivers invitation only", async () => {
  const output: string[] = []; const input = ["220 ready\r\n", "250-server\r\n250 STARTTLS\r\n", "220 TLS\r\n", "250 server\r\n", "235 authenticated\r\n", "250 sender\r\n", "250 recipient\r\n", "354 data\r\n", "250 queued\r\n", "221 bye\r\n"];
  const socket: SmtpConnection = { read: async buffer => { const next = input.shift(); if (!next) return null; const bytes = new TextEncoder().encode(next); buffer.set(bytes); return bytes.length; }, write: async bytes => { output.push(new TextDecoder().decode(bytes)); return bytes.length; }, close: () => {} };
  const env = { get: (name: string) => ({ SMTP_HOST: "smtp.example.com", SMTP_PORT: "587", SMTP_ADMIN_EMAIL: "sender@example.com", SMTP_USER: "sender", SMTP_PASS: "test-password" } as Record<string, string>)[name] };
  await sendInvitationEmail(env, "member@example.com", "https://app.example.com/shared/join/token", { connect: async () => socket, startTls: async () => { output.push("TLS"); return socket; } });
  equal(output[0], "EHLO pomodoist\r\n"); equal(output[1], "STARTTLS\r\n"); equal(output[2], "TLS");
  equal(output[4].startsWith("AUTH PLAIN "), true); equal(output[7], "DATA\r\n"); equal(output[8].includes("https://app.example.com/shared/join/token"), true);
});
Deno.test("SMTP cannot send credentials or DATA if STARTTLS is rejected", async () => {
  const sent: string[] = []; const replies = ["220 ready\r\n", "250 ready\r\n", "500 TLS unavailable\r\n"];
  const socket: SmtpConnection = { read: async b => { const bytes = new TextEncoder().encode(replies.shift()); b.set(bytes); return bytes.length; }, write: async b => { sent.push(new TextDecoder().decode(b)); return b.length; }, close: () => {} };
  let failed = false;
  try { await sendInvitationEmail({ get: n => ({ SMTP_HOST: "smtp.example.com", SMTP_ADMIN_EMAIL: "sender@example.com", SMTP_USER: "user", SMTP_PASS: "secret" } as Record<string, string>)[n] }, "member@example.com", "https://app.example.com/join", { connect: async () => socket, startTls: async () => socket }); } catch { failed = true; }
  equal(failed, true); equal(sent, ["EHLO pomodoist\r\n", "STARTTLS\r\n"]);
});

Deno.test("public projection excludes directory, email, file paths, focus and internal author IDs", () => {
  const result = publicCollaborationProjection({ scopeId: "s", rootProjectId: "p", ownerId: "secret", members: [{ email: "secret@example.com" }], entities: [
    { id: "t", entityType: "task", data: { content: "Public task", createdBy: "user", userId: "user", email: "secret@example.com", assigneeIds: ["user"], assigneeNames: ["Display name"], totalFocusSeconds: 100, objectPath: "secret/path" } },
    { id: "a", entityType: "attachment", data: { objectPath: "secret/path" } },
    { id: "f", entityType: "focus_interval", data: { durationSeconds: 100 } },
  ] });
  equal(result, { scope: { id: "s", rootProjectId: "p" }, projects: [], tasks: [{ content: "Public task", assigneeNames: ["Display name"], id: "t" }], comments: [] });
});

Deno.test("private preference requests preserve caller identity at the RPC boundary", async () => {
  const f = fixture({ preferences: [{ scopeId: "s", entityType: "scope", entityId: "s", data: { rootParentId: "personal" } }] });
  const request = { action: "preferences", scopeId: "s", entityType: "scope", entityId: "s", data: { rootParentId: "personal" } };
  equal(validateCollaborationRequest(request), request);
  rejects(() => validateCollaborationRequest({ ...request, data: [] }));
  const response = await handleCollaboration(f.request(request), f.deps);
  equal(response.status, 200); equal(f.calls, ["auth", "rpc:preferences"]);
});
