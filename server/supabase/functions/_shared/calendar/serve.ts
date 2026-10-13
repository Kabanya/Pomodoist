import { createClient } from "npm:@supabase/supabase-js@2.115.0";
import { calendarHandler } from "./runtime.ts";
import { CalendarTokenClient } from "./tokens.ts";
import {
  type CalendarRpc,
  decodeConnection,
  RpcCalendarStore,
} from "./store.ts";
import { processConnection } from "./worker.ts";
import { randomToken, record, sha256 } from "./security.ts";
import { GoogleAdapter } from "../../pomodoist-google-calendar/google_calendar_adapter.ts";
import { GraphCalendarApi } from "../../pomodoist-outlook-calendar/graph_adapter.ts";
import { OutlookAdapter } from "../../pomodoist-outlook-calendar/outlook_adapter.ts";

export function serveCalendar(provider: "google" | "outlook"): void {
  const prefix = provider === "google" ? "GOOGLE_CALENDAR" : "OUTLOOK_CALENDAR";
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const publicUrl = Deno.env.get(`${prefix}_FUNCTION_URL`) ??
    `${url}/functions/v1/pomodoist-${provider}-calendar`;
  const clientId = Deno.env.get(`${prefix}_CLIENT_ID`) ?? "";
  const clientSecret = Deno.env.get(`${prefix}_CLIENT_SECRET`) ?? "";
  const workerSecret = Deno.env.get(`${prefix}_WORKER_SECRET`) ?? "";
  const admin = createClient(
    url,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );
  const tokens = new CalendarTokenClient(
    provider,
    clientId,
    clientSecret,
    publicUrl,
  );
  const rpc: CalendarRpc = async (action, userId, selected, payload) => {
    const { data, error } = await admin.rpc("pomodoist_calendar_service", {
      p_action: action,
      p_user_id: userId,
      p_provider: selected,
      p_payload: payload,
    });
    if (error) throw new Error("Calendar persistence is unavailable.");
    return data;
  };
  const store = new RpcCalendarStore(rpc);
  const configure = () =>
    rpc("configure", null, provider, { url: publicUrl, secret: workerSecret });
  Deno.serve((req) =>
    calendarHandler(req, {
      provider,
      workerSecret,
      actions: {
        provider,
        clientId,
        configured: !!clientId && !!clientSecret && workerSecret.length >= 16,
        redirectUri: publicUrl,
        appRedirectUri: Deno.env.get(`${prefix}_APP_REDIRECT_URI`) ??
          `pomodoist://${provider}-calendar-connected`,
        authenticate: async (authorization) => {
          if (!authorization.startsWith("Bearer ")) return null;
          const client = createClient(
            url,
            Deno.env.get("SUPABASE_ANON_KEY") ?? "",
            { global: { headers: { Authorization: authorization } } },
          );
          const { data: { user }, error } = await client.auth.getUser();
          return error ? null : user?.id ?? null;
        },
        storeState: async (input) => {
          await configure();
          await rpc("store_state", String(input.userId), provider, input);
        },
        consumeState: async (stateHash) => {
          const value = await rpc("consume_state", null, provider, {
            stateHash,
          });
          return record(value) && typeof value.userId === "string" &&
              typeof value.verifier === "string"
            ? { userId: value.userId, verifier: value.verifier }
            : null;
        },
        exchange: (code, verifier) => tokens.exchange(code, verifier),
        connect: async (userId, authorization) => {
          await configure();
          await rpc("connect", userId, provider, {
            refreshToken: authorization.refreshToken,
            accountId: authorization.accountId,
            accountEmail: authorization.accountEmail,
          });
        },
        sync: async (userId) => {
          await configure();
          await rpc("queue", userId, provider, {});
        },
        disconnect: async (userId) => {
          await rpc("disconnect", userId, provider, {});
        },
      },
      notifications: {
        lookup: async (subscriptionId) => {
          const value = await rpc("subscription", null, provider, {
            subscriptionId,
          });
          return record(value) && typeof value.connectionId === "string" &&
              typeof value.clientStateHash === "string"
            ? {
              connectionId: value.connectionId,
              generation: Number(value.generation),
              clientStateHash: value.clientStateHash,
              resource: String(value.resource),
            }
            : null;
        },
        enqueue: async (connectionId, generation, work) => {
          await rpc("enqueue_notification", null, provider, {
            connectionId,
            generation,
            work,
          });
        },
      },
      googleWebhook: async (payload) => {
        const result = await rpc("google_webhook", null, provider, payload);
        return record(result) && result.accepted === true;
      },
      runWorker: async () => {
        const claimed = await rpc("claim", null, provider, {});
        if (!Array.isArray(claimed)) throw new Error("Invalid calendar claim.");
        let succeeded = 0;
        await Promise.allSettled(claimed.map(async (raw) => {
          const connection = decodeConnection(raw);
          const guard = {
            connectionId: connection.id,
            generation: connection.generation,
            lease: connection.lease,
          };
          try {
            let credential = raw.credentials;
            if (typeof credential === "string") {
              try {
                credential = JSON.parse(credential);
              } catch {
                credential = { refreshToken: credential };
              }
            }
            if (
              !record(credential) || typeof credential.refreshToken !== "string"
            ) throw new Error("Calendar credential is missing.");
            const refreshed = await tokens.refresh(credential.refreshToken);
            if (refreshed.refreshToken !== credential.refreshToken) {
              await rpc("refresh_token", connection.userId, provider, {
                guard,
                refreshToken: refreshed.refreshToken,
              });
            }
            if (provider === "outlook" && !connection.state.clientState) {
              const clientState = randomToken();
              connection.state = {
                ...connection.state,
                clientState,
                clientStateHash: await sha256(clientState),
                notificationUrl:
                  `${publicUrl}/notifications?registration=${connection.id}-${connection.generation}`,
                lifecycleUrl: `${publicUrl}/lifecycle`,
              };
            }
            if (connection.state.cleanupPending === true) {
              if (
                provider === "outlook" &&
                typeof connection.state.subscriptionId === "string"
              ) {
                const graph = new GraphCalendarApi(refreshed.accessToken);
                try {
                  await graph.request(
                    `/subscriptions/${
                      encodeURIComponent(connection.state.subscriptionId)
                    }`,
                    { method: "DELETE" },
                  );
                } catch (error) {
                  if (
                    !(error && typeof error === "object" && "status" in error &&
                      error.status === 404)
                  ) throw error;
                }
              } else if (
                provider === "google" && connection.state.watchChannelId
              ) {
                const google = new GoogleAdapter(
                  refreshed.accessToken,
                  connection.id,
                  connection.calendarId,
                  connection.state,
                  publicUrl,
                );
                await google.request("/channels/stop", {
                  method: "POST",
                  body: {
                    id: connection.state.watchChannelId,
                    resourceId: connection.state.watchResourceId,
                  },
                });
              }
              await rpc("cleanup_complete", connection.userId, provider, {
                guard,
              });
            } else {
              const adapter = provider === "outlook"
                ? new OutlookAdapter(
                  new GraphCalendarApi(refreshed.accessToken),
                  connection.id,
                  connection.calendarId,
                )
                : new GoogleAdapter(
                  refreshed.accessToken,
                  connection.id,
                  connection.calendarId,
                  connection.work.recovery
                    ? { ...connection.state, syncToken: null }
                    : connection.state,
                  publicUrl,
                );
              await processConnection(connection, store, adapter);
            }
            succeeded++;
          } catch (error) {
            if (
              connection.state.cleanupPending === true && error &&
              typeof error === "object" && "status" in error &&
              [401, 403].includes(Number(error.status))
            ) {
              // Revoked provider access cannot remove a subscription; it expires remotely.
              await rpc("cleanup_complete", connection.userId, provider, {
                guard,
              });
              succeeded++;
            } else await store.fail(connection, error);
          }
        }));
        return {
          claimed: claimed.length,
          succeeded,
          failed: claimed.length - succeeded,
        };
      },
    })
  );
}
