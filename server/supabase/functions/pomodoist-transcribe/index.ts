import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import { handleVoiceTranscription } from "./transcribe.ts";

Deno.serve((request) => handleVoiceTranscription(request, {
  env: Deno.env,
  fetch,
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
    // or locally decoding an unverified JWT. No service-role key is necessary.
    const { data, error } = await client.auth.getUser();
    if (error) {
      if (error.status && error.status < 500) return null;
      throw new Error("Account verification unavailable");
    }
    return data.user?.is_anonymous ? null : data.user?.id ?? null;
  },
}));
