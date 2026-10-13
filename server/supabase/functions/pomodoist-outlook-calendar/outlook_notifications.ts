import { readLimitedJson } from "../_shared/limited_json.ts";
import {
  constantTimeEqual,
  record,
  sha256,
} from "../_shared/calendar/security.ts";
import {
  emptyWork,
  mergeWork,
  type Work,
  type WorkInput,
} from "../_shared/calendar/work.ts";
export type NotificationDeps = {
  lookup: (
    subscriptionId: string,
  ) => Promise<
    {
      connectionId: string;
      generation: number;
      clientStateHash: string;
      resource: string;
    } | null
  >;
  enqueue: (
    connectionId: string,
    generation: number,
    work: WorkInput,
  ) => Promise<void>;
};
export async function handleOutlookNotifications(
  req: Request,
  deps: NotificationDeps,
): Promise<Response> {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  const validation = new URL(req.url).searchParams.get("validationToken");
  if (validation !== null) {
    return validation.length <= 4096
      ? new Response(validation, {
        headers: {
          "Content-Type": "text/plain; charset=utf-8",
          "X-Content-Type-Options": "nosniff",
        },
      })
      : new Response(null, { status: 413 });
  }
  const parsed = await readLimitedJson(req, 512 * 1024);
  if (!parsed.ok) return new Response(null, { status: parsed.status });
  if (!record(parsed.value) || !Array.isArray(parsed.value.value)) {
    return new Response(null, { status: 400 });
  }
  if (parsed.value.value.length > 1000) {
    return new Response(null, { status: 413 });
  }
  const queued = new Map<string, { generation: number; work: Work }>();
  try {
    for (const item of parsed.value.value) {
      if (
        !record(item) || typeof item.subscriptionId !== "string" ||
        typeof item.clientState !== "string" || item.clientState.length > 128
      ) continue;
      const subscription = await deps.lookup(item.subscriptionId);
      if (
        !subscription ||
        !constantTimeEqual(
          await sha256(item.clientState),
          subscription.clientStateHash,
        )
      ) continue;
      if (!/^(\/)?(me|users\/[^/]+)\/events$/i.test(subscription.resource)) {
        continue;
      }
      let work: WorkInput;
      if (
        ["missed", "subscriptionRemoved", "reauthorizationRequired"].includes(
          String(item.lifecycleEvent),
        )
      ) {
        work = {
          maintenance: true,
          recovery: item.lifecycleEvent !== "reauthorizationRequired",
        };
      } else {
        if (
          !["created", "updated", "deleted"].includes(String(item.changeType))
        ) continue;
        const resource = record(item.resourceData) ? item.resourceData : {};
        if (
          resource["@odata.type"] &&
          resource["@odata.type"] !== "#Microsoft.Graph.Event"
        ) continue;
        if (typeof resource.id !== "string" || resource.id.length > 2048) {
          work = { recovery: true };
        } else {work = {
            hints: [{
              eventId: resource.id,
              version: typeof resource["@odata.etag"] === "string"
                ? resource["@odata.etag"]
                : null,
              kind: item.changeType as "created" | "updated" | "deleted",
            }],
          };}
      }
      const previous = queued.get(subscription.connectionId);
      queued.set(subscription.connectionId, {
        generation: subscription.generation,
        work: mergeWork(previous?.work ?? emptyWork(), work),
      });
    }
    for (const [id, item] of queued) {
      await deps.enqueue(id, item.generation, item.work);
    }
    return new Response(null, { status: 202 });
  } catch {
    return new Response(null, {
      status: 503,
      headers: { "Retry-After": "10" },
    });
  }
}
