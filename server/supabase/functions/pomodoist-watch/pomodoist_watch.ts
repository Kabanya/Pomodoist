import {
  appId,
  arrayValue,
  type JsonMap,
  mapValue,
  numberValue,
  type PomodoistOperation,
  type PomodoistState,
  pomodoistState,
  type PomodoistSyncEntity,
  stringValue,
  type SupabaseClient,
} from "../_shared/pomodoist_state.ts";
import {
  commitDraftOps,
  completeTaskOps,
  taskCreateOps,
  uncompleteTaskOps,
} from "../_shared/pomodoist_task_commands.ts";
import {
  focusStartOps,
  focusUpdateOps,
} from "../_shared/pomodoist_focus_commands.ts";
import { buildSnapshot } from "../_shared/pomodoist_snapshots.ts";
import {
  corsHeaders,
  handleTaskDecomposition,
  json,
  type PomodoistWatchDeps,
  readJson,
} from "../_shared/task_decomposition_http.ts";
export {
  corsHeaders,
  type PomodoistWatchDeps,
} from "../_shared/task_decomposition_http.ts";
export {
  type PomodoistOperation,
  type PomodoistState,
  pomodoistState,
  type PomodoistSyncEntity,
} from "../_shared/pomodoist_state.ts";
export { telegramCommandOps } from "../_shared/pomodoist_commands.ts";
export { telegramSnapshot } from "../_shared/pomodoist_snapshots.ts";
export async function handlePomodoistWatch(
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

  const deviceId = stringValue(body.deviceId) ?? "apple-watch";
  const command = mapValue(body.command) ?? body;
  const type = stringValue(command.type) ?? "snapshot.request";
  const now = deps.now?.() ?? new Date();
  const uuid = deps.uuid ?? (() => crypto.randomUUID());
  const authorization = req.headers.get("Authorization");
  const client = authorization ? deps.createClient(authorization) : null;
  const user = client ? (await client.auth.getUser()).data.user : null;

  if (type === "task.decomposeTranscript") {
    return handleTaskDecomposition(body, command, user, deps, now);
  }

  if (!client || !user) {
    return json({ ok: false, error: "Unauthorized." }, 401);
  }

  try {
    let state = await loadState(client);
    let extra: JsonMap = {};
    let appliedCommandId = stringValue(command.id);
    let includeSnapshot = true;
    let ops: PomodoistOperation[] = [];

    switch (type) {
      case "snapshot.request":
        break;
      case "task.createQuickAdd":
        ops = taskCreateOps(state, command, user, now, uuid);
        break;
      case "task.commitDrafts":
        ops = await commitDraftOps(state, command, user, now, uuid);
        break;
      case "task.complete":
        ops = completeTaskOps(state, command, user, now, uuid);
        break;
      case "task.uncomplete":
        ops = uncompleteTaskOps(state, command, user, now);
        break;
      case "focus.startDefault":
        ops = focusStartOps(state, command, user, now, uuid);
        break;
      case "focus.pause":
      case "focus.resume":
      case "focus.restartInterval":
      case "focus.complete":
      case "focus.skip":
      case "focus.stop":
        ops = focusUpdateOps(state, command, user, now, uuid);
        break;
      default:
        return json(
          { ok: false, error: `Unsupported watch command: ${type}` },
          400,
        );
    }

    if (ops.length > 0) {
      if (type === "task.commitDrafts") {
        const { error } = await client.rpc("push_pomodoist_draft_changes", {
          p_device_id: deviceId,
          p_command_id: ops[0].opId,
          p_operations: ops,
        });
        if (error) throw new Error(error.message);
      } else {
        await pushChanges(client, deviceId, ops);
      }
      state = await loadState(client);
    }

    return json({
      ok: true,
      ...extra,
      ...(appliedCommandId == null ? {} : { appliedCommandId }),
      ...(includeSnapshot ? { snapshot: buildSnapshot(state, now) } : {}),
    });
  } catch (error) {
    return json({ ok: false, error: `${error}` }, 400);
  }
}

async function loadState(
  client: SupabaseClient,
): Promise<PomodoistState> {
  let cursor = 0;
  const entities: PomodoistSyncEntity[] = [];
  // The RPC filters irrelevant histories; paginate until every task is loaded.
  while (true) {
    const { data, error } = await client.rpc("read_pomodoist_companion_state", {
      p_since_revision: cursor,
    });
    if (error) {
      throw new Error(error.message);
    }
    const page = mapValue(data) ?? {};
    for (const item of arrayValue(page.changes)) {
      const entity = mapValue(item);
      if (entity == null) continue;
      const serverRevision =
        numberValue(entity.serverRevision ?? entity.server_revision) ?? 0;
      entities.push({
        entityType: stringValue(entity.entityType ?? entity.entity_type) ?? "",
        entityId: stringValue(entity.entityId ?? entity.entity_id) ?? "",
        serverRevision,
        deletedAt: stringValue(entity.deletedAt ?? entity.deleted_at),
        data: mapValue(entity.data) ?? {},
      });
    }
    const nextCursor = numberValue(page.nextCursor ?? page.next_cursor) ??
      cursor;
    const hasMore = Boolean(page.hasMore ?? page.has_more);
    cursor = nextCursor;
    if (!hasMore) break;
  }

  return pomodoistState(entities);
}

async function pushChanges(
  client: SupabaseClient,
  deviceId: string,
  operations: PomodoistOperation[],
) {
  const { error } = await client.rpc("push_changes", {
    p_app_id: appId,
    p_device_id: deviceId,
    p_operations: operations,
  });
  if (error) {
    throw new Error(error.message);
  }
}
