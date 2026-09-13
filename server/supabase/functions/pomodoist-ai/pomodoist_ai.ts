import {
  corsHeaders,
  handleTaskDecomposition,
  json,
  type PomodoistWatchDeps,
  readJson,
} from "../_shared/task_decomposition_http.ts";
import { mapValue, stringValue } from "../_shared/pomodoist_state.ts";

export async function handlePomodoistAi(
  req: Request,
  deps: PomodoistWatchDeps,
) {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ ok: false, error: "Method not allowed." }, 405);
  }
  const body = await readJson(req);
  if (body == null) {
    return json({ ok: false, error: "Request body must be valid JSON." }, 400);
  }
  const command = mapValue(body.command) ?? body;
  const type = stringValue(command.type);
  if (type !== "task.decomposeTranscript") {
    return json({ ok: false, error: `Unsupported AI command: ${type}` }, 400);
  }
  const authorization = req.headers.get("Authorization");
  const client = authorization ? deps.createClient(authorization) : null;
  const user = client ? (await client.auth.getUser()).data.user : null;
  return handleTaskDecomposition(
    body,
    command,
    user,
    deps,
    deps.now?.() ?? new Date(),
  );
}
