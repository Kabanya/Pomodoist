import { createClient } from "npm:@supabase/supabase-js@2.115.0";
import { CollaborationError, type CollaborationDependencies } from "./pomodoist_collaboration.ts";
import { sendInvitationEmail } from "./pomodoist_collaboration_mail.ts";

declare const EdgeRuntime: { waitUntil(task: Promise<unknown>): void };

export function collaborationRuntime(settings: {
  url: string; publicUrl?: string; key: string; webUrl: string; env: { get(name: string): string | undefined };
  fetcher?: typeof fetch;
  authenticate?: CollaborationDependencies['authenticate'];
  rpc?: CollaborationDependencies['rpc'];
}): CollaborationDependencies {
const { url, key } = settings;
const publicAddress = (address: string) => {
  const internal = url.replace(/\/+$/, "");
  return address.startsWith(`${internal}/`) ? `${(settings.publicUrl ?? url).replace(/\/+$/, "")}${address.slice(internal.length)}` : address;
};
const options = { global: { fetch: (input: RequestInfo | URL, init?: RequestInit) => (settings.fetcher ?? fetch)(input, { ...init, signal: AbortSignal.timeout(20000) }) }, auth: { persistSession: false, autoRefreshToken: false } };
const admin = createClient(url, key, options);
const client = (authorization: string | null) => authorization ? createClient(url, key, { ...options, global: { ...options.global, headers: { Authorization: authorization } } }) : admin;
return {
  webUrl: settings.webUrl,
  waitUntil: typeof EdgeRuntime === "undefined" ? undefined : task => EdgeRuntime.waitUntil(task),
  authenticate: settings.authenticate ?? (async authorization => {
    const { data, error } = await client(authorization).auth.getUser();
    return error || data.user?.is_anonymous ? null : data.user?.id ?? null;
  }),
  rpc: settings.rpc ?? (async (authorization, input) => {
    const { data, error } = await client(authorization).rpc("pomodoist_collaboration", { p_request: input }).abortSignal(AbortSignal.timeout(20000));
    if (error) throw new CollaborationError(error.message, error.code, error.code === "42501" ? 403 : error.code === "40001" ? 409 : error.code === "54000" ? 429 : 400);
    return data;
  }),
  upload: async path => {
    const { data, error } = await admin.storage.from("pomodoist-shared").createSignedUploadUrl(path, { upsert: false });
    if (error || !data) throw new Error("Upload URL unavailable");
    return { signedUrl: publicAddress(data.signedUrl), token: data.token };
  },
  download: async (path, name) => {
    const { data, error } = await admin.storage.from("pomodoist-shared").createSignedUrl(path, 60, { download: name });
    if (error || !data) throw new Error("Download URL unavailable");
    return publicAddress(data.signedUrl);
  },
  cleanup: async () => {
    const { data, error } = await admin.rpc("pomodoist_collaboration_storage_cleanup");
    if (error || !data?.paths?.length) return;
    const result = await admin.storage.from("pomodoist-shared").remove(data.paths);
    if (!result.error) await admin.rpc("pomodoist_collaboration_storage_cleanup", { p_deleted: data.paths });
  },
  inviteEmail: (email, link) => sendInvitationEmail(settings.env, email, link),
};
}
