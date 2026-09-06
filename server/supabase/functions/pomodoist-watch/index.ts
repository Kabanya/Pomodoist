import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import { handlePomodoistWatch } from "./pomodoist_watch.ts";

Deno.serve((req) =>
  handlePomodoistWatch(req, {
    env: Deno.env,
    fetch,
    createClient: (authorization) => {
      const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
      const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
      return createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: authorization } },
      });
    },
  })
);
