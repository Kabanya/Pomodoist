import { handleCollaboration } from "../_shared/pomodoist_collaboration.ts";
import { collaborationRuntime } from "../_shared/pomodoist_collaboration_runtime.ts";
const dependencies = collaborationRuntime({
  url: Deno.env.get("SUPABASE_URL") ?? "",
  publicUrl: Deno.env.get("SUPABASE_PUBLIC_URL"),
  key: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  webUrl: Deno.env.get("POMODOIST_WEB_URL") ?? "https://app.pomodoist.com",
  env: Deno.env,
});
Deno.serve(request => handleCollaboration(request, dependencies));
