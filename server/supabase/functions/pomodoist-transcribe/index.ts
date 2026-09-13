import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import { handleVoiceTranscription } from "./transcribe.ts";

const quotaClient = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  { auth: { persistSession: false, autoRefreshToken: false } },
);

Deno.serve((request) => handleVoiceTranscription(request, {
  env: Deno.env,
  fetch,
  quota: async (action, userId, requestId) => {
    // Retry ambiguous network failures with the same server-generated ID.
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const { data, error } = await quotaClient.rpc("pomodoist_voice_quota", {
          p_action: action, p_user_id: userId, p_request_id: requestId,
        }).abortSignal(AbortSignal.timeout(5000));
        if (error || !data || typeof data.allowed !== "boolean") throw new Error("Quota unavailable");
        return data;
      } catch {
        if (attempt === 1) throw new Error("Quota unavailable");
      }
    }
    throw new Error("Quota unavailable");
  },
  authenticate: async (authorization) => {
    const client = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_ANON_KEY") ?? "",
      {
        global: {
          headers: { Authorization: authorization },
          fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(10000) }),
        },
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );
    // Validate the user with Auth, never by trusting a client-supplied user ID
    // or locally decoding an unverified JWT. Only that verified ID reaches quota RPCs.
    const { data, error } = await client.auth.getUser();
    if (error) {
      if (error.status && error.status < 500) return null;
      throw new Error("Account verification unavailable");
    }
    return data.user?.is_anonymous ? null : data.user?.id ?? null;
  },
}));
