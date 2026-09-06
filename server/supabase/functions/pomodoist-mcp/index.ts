import "@supabase/functions-js/edge-runtime.d.ts";

import { configFromEnv, createPomodoistMcpHandler } from "./pomodoist_mcp.ts";
import { registerPomodoistTools } from "./tools.ts";

const config = configFromEnv();
const log = (entry: Record<string, unknown>) =>
  console.log(JSON.stringify(entry));

Deno.serve(createPomodoistMcpHandler({
  config,
  log,
  registerTools: (server, auth) =>
    registerPomodoistTools(server, auth, { config, log }),
}));
