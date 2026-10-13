import { GraphError, type JsonMap } from "./graph_adapter.ts";
export type SubscriptionState = {
  id: string | null;
  expiresAt: string | null;
  notificationUrl: string;
  lifecycleUrl: string;
  clientState: string;
  resource: string;
};
export type SubscriptionRequest = (
  path: string,
  options?: { method?: string; body?: JsonMap },
) => Promise<JsonMap>;
export async function maintainSubscription(
  state: SubscriptionState,
  request: SubscriptionRequest,
  now = new Date(),
): Promise<{ state: SubscriptionState; replaced: boolean }> {
  const day = 24 * 60 * 60 * 1000;
  if (
    state.id && state.expiresAt &&
    Date.parse(state.expiresAt) > now.getTime() + day
  ) return { state, replaced: false };
  const expirationDateTime = new Date(now.getTime() + 2 * day).toISOString();
  if (state.id) {
    try {
      const renewed = await request(
        `/subscriptions/${encodeURIComponent(state.id)}`,
        { method: "PATCH", body: { expirationDateTime } },
      );
      return { state: accepted(state, renewed), replaced: false };
    } catch (error) {
      if (!(error instanceof GraphError) || error.status !== 404) throw error;
    }
  }
  let next: string | null = "/subscriptions";
  const visited = new Set<string>();
  while (next) {
    if (visited.has(next)) throw new Error("Subscription paging cycle.");
    visited.add(next);
    const page = await request(next);
    if (!Array.isArray(page.value)) {
      throw new Error("Invalid subscription listing.");
    }
    const existing = page.value.find((item) =>
      item.notificationUrl === state.notificationUrl &&
      item.resource.replace(/^\//, "") === state.resource.replace(/^\//, "")
    );
    if (existing) {
      const recovered = accepted(state, existing);
      if (Date.parse(recovered.expiresAt!) > now.getTime() + day) {
        return { state: recovered, replaced: true };
      }
      const renewed = await request(
        `/subscriptions/${encodeURIComponent(recovered.id!)}`,
        { method: "PATCH", body: { expirationDateTime } },
      );
      return { state: accepted(recovered, renewed), replaced: true };
    }
    next = typeof page["@odata.nextLink"] === "string"
      ? page["@odata.nextLink"]
      : null;
  }
  const created = await request("/subscriptions", {
    method: "POST",
    body: {
      changeType: "created,updated,deleted",
      notificationUrl: state.notificationUrl,
      lifecycleNotificationUrl: state.lifecycleUrl,
      resource: state.resource,
      clientState: state.clientState,
      expirationDateTime,
      includeResourceData: false,
    },
  });
  return { state: accepted(state, created), replaced: true };
}
function accepted(state: SubscriptionState, value: JsonMap): SubscriptionState {
  if (
    typeof value.id !== "string" ||
    typeof value.expirationDateTime !== "string" ||
    !Number.isFinite(Date.parse(value.expirationDateTime))
  ) throw new Error("Invalid Graph subscription response.");
  return { ...state, id: value.id, expiresAt: value.expirationDateTime };
}
