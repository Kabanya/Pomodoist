import { apiVersionError } from "../api_version.ts";
import { readLimitedJson } from "../limited_json.ts";
import { base64Url, randomToken, record, sha256 } from "./security.ts";
import type { CalendarProvider } from "./reconcile.ts";
export type CalendarTokens = {
  accessToken: string;
  refreshToken: string;
  accountId: string;
  accountEmail: string | null;
};
export type CalendarActionDeps = {
  provider: CalendarProvider;
  clientId: string;
  configured: boolean;
  redirectUri: string;
  appRedirectUri: string;
  authenticate: (authorization: string) => Promise<string | null>;
  storeState: (value: Record<string, unknown>) => Promise<void>;
  consumeState: (
    hash: string,
  ) => Promise<{ userId: string; verifier: string } | null>;
  exchange: (code: string, verifier: string) => Promise<CalendarTokens>;
  connect: (userId: string, tokens: CalendarTokens) => Promise<void>;
  sync: (userId: string) => Promise<void>;
  disconnect: (userId: string) => Promise<void>;
};
export async function handleCalendarActions(
  req: Request,
  deps: CalendarActionDeps,
): Promise<Response> {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);
  try {
    if (req.method === "GET") {
      const state = url.searchParams.get("state");
      if (!state || state.length > 512) {
        return json({ error: "Invalid OAuth callback." }, 400);
      }
      const pending = await deps.consumeState(await sha256(state));
      if (!pending) {
        return json({ error: "OAuth state expired or was already used." }, 400);
      }
      const code = url.searchParams.get("code");
      if (!code || url.searchParams.has("error")) {
        return json({ error: "Calendar authorization was cancelled." }, 400);
      }
      const tokens = await deps.exchange(code, pending.verifier);
      if (!tokens.refreshToken || !tokens.accountId) {
        return json({
          error: "Calendar authorization did not grant offline access.",
        }, 400);
      }
      await deps.connect(pending.userId, tokens);
      return Response.redirect(deps.appRedirectUri, 302);
    }
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }
    const userId = await deps.authenticate(
      req.headers.get("Authorization") ?? "",
    );
    if (!userId) return json({ error: "Authentication required." }, 401);
    const parsed = await readLimitedJson(req, 16384);
    if (!parsed.ok) return json({ error: parsed.error }, parsed.status);
    const versionError = apiVersionError(parsed.value);
    if (versionError) return json(versionError, 400);
    if (!record(parsed.value)) return json({ error: "Invalid request." }, 400);
    switch (parsed.value.action) {
      case "start": {
        if (!deps.configured) {
          return json(
            { error: "Calendar integration is not configured." },
            503,
          );
        }
        const state = randomToken();
        const verifier = randomToken(64);
        const challenge = base64Url(
          new Uint8Array(
            await crypto.subtle.digest(
              "SHA-256",
              new TextEncoder().encode(verifier),
            ),
          ),
        );
        await deps.storeState({
          userId,
          stateHash: await sha256(state),
          verifier,
          expiresAt: new Date(Date.now() + 600000).toISOString(),
        });
        const microsoft = deps.provider === "outlook";
        const target = new URL(
          microsoft
            ? "https://login.microsoftonline.com/common/oauth2/v2.0/authorize"
            : "https://accounts.google.com/o/oauth2/v2/auth",
        );
        target.search = new URLSearchParams({
          client_id: deps.clientId,
          redirect_uri: deps.redirectUri,
          response_type: "code",
          state,
          scope: microsoft
            ? "openid profile email offline_access https://graph.microsoft.com/Calendars.ReadWrite https://graph.microsoft.com/User.Read"
            : "openid email https://www.googleapis.com/auth/calendar.app.created https://www.googleapis.com/auth/calendar.calendarlist.readonly",
          code_challenge: challenge,
          code_challenge_method: "S256",
          ...(microsoft
            ? { response_mode: "query", prompt: "select_account" }
            : { access_type: "offline", prompt: "consent" }),
        }).toString();
        return json({ authorizationUrl: target.toString() });
      }
      case "sync":
        await deps.sync(userId);
        return json({ queued: true });
      case "disconnect":
        await deps.disconnect(userId);
        return json({ disconnected: true });
      default:
        return json({ error: "Unsupported action." }, 400);
    }
  } catch {
    return json({ error: "Calendar service is unavailable." }, 503);
  }
}
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
function json(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: cors });
}
