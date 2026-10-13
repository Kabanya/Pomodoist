import { constantTimeEqual, sha256 } from "./security.ts";
import { type CalendarActionDeps, handleCalendarActions } from "./actions.ts";
import {
  handleOutlookNotifications,
  type NotificationDeps,
} from "../../pomodoist-outlook-calendar/outlook_notifications.ts";
export type RuntimeDeps = {
  provider: "google" | "outlook";
  workerSecret: string;
  actions: CalendarActionDeps;
  notifications: NotificationDeps;
  googleWebhook: (input: Record<string, unknown>) => Promise<boolean>;
  runWorker: () => Promise<
    { claimed: number; succeeded: number; failed: number }
  >;
};
export async function calendarHandler(
  req: Request,
  deps: RuntimeDeps,
): Promise<Response> {
  const url = new URL(req.url);
  try {
    if (
      deps.provider === "outlook" &&
      (url.pathname.endsWith("/notifications") ||
        url.pathname.endsWith("/lifecycle"))
    ) return await handleOutlookNotifications(req, deps.notifications);
    if (req.headers.has("X-Pomodoist-Worker-Secret")) {
      if (
        req.method !== "POST" ||
        !constantTimeEqual(
          req.headers.get("X-Pomodoist-Worker-Secret") ?? "",
          deps.workerSecret,
        )
      ) return new Response(null, { status: 401 });
      return Response.json(await deps.runWorker());
    }
    if (deps.provider === "google" && req.headers.has("X-Goog-Channel-ID")) {
      if (req.method !== "POST") return new Response(null, { status: 405 });
      const channelId = req.headers.get("X-Goog-Channel-ID");
      const resourceId = req.headers.get("X-Goog-Resource-ID");
      const token = req.headers.get("X-Goog-Channel-Token");
      if (!channelId || !resourceId || !token) {
        return new Response(null, { status: 401 });
      }
      const accepted = await deps.googleWebhook({
        channelId,
        resourceId,
        tokenHash: await sha256(token),
      });
      return new Response(null, { status: accepted ? 204 : 401 });
    }
    return await handleCalendarActions(req, deps.actions);
  } catch {
    return Response.json({ error: "Calendar service is unavailable." }, {
      status: 503,
    });
  }
}
