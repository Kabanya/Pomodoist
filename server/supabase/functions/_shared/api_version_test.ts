import { assertEquals } from "@std/assert";
import { apiVersionError } from "./api_version.ts";
import { handleAccountDelete } from "../account-delete/index.ts";
import { handlePomodoistAi } from "../pomodoist-ai/pomodoist_ai.ts";
import { handlePomodoistWatch } from "../pomodoist-watch/pomodoist_watch.ts";
import { handlePomodoistPurchase } from "../pomodoist-purchase/pomodoist_purchase.ts";
import { handlePomodoistStripeBilling } from "../pomodoist-stripe-billing/pomodoist_stripe_billing.ts";
import { handleSubscriptionOffer } from "../pomodoist-subscription-offer/pomodoist_subscription_offer.ts";
import { handlePomodoistGoogleCalendar } from "../pomodoist-google-calendar/pomodoist_google_calendar.ts";
import { handlePomodoistTelegram } from "../pomodoist-telegram/pomodoist_telegram.ts";
import { handleVoiceTranscription } from "../pomodoist-transcribe/transcribe.ts";
import { handleCollaboration } from "./pomodoist_collaboration.ts";

Deno.test("API version accepts legacy and v1 without coercion", () => {
  for (const body of [{}, { apiVersion: 0 }, { apiVersion: 1 }]) assertEquals(apiVersionError(body), null);
  for (const version of [null, "1", 2, -1, 0.5, true, [], {}]) {
    assertEquals(apiVersionError({ apiVersion: version })?.code, "unsupported_api_version");
  }
});

const handlers = [handleAccountDelete, handlePomodoistAi, handlePomodoistWatch,
  handlePomodoistPurchase, handlePomodoistStripeBilling, handleSubscriptionOffer,
  handlePomodoistGoogleCalendar, handlePomodoistTelegram, handleVoiceTranscription,
  handleCollaboration];
for (const handler of handlers) {
  Deno.test(`${handler.name} rejects future versions before mutations`, async () => {
    let unexpectedCalls = 0;
    const deps = new Proxy({
      allowedOrigin: "https://example.test",
      enabled: false,
      authenticate: () => Promise.resolve({ id: "user", userId: "user", accountToken: "token" }),
      env: { get: (key: string) => key === "POMODOIST_OPENROUTER_API_KEY" ? "test-key" : undefined },
    }, { get(target, name) {
      if (name in target) return Reflect.get(target, name);
      return () => { unexpectedCalls++; throw new Error(`Unexpected ${String(name)}`); };
    }});
    const response = await (handler as unknown as (request: Request, deps: unknown) => Promise<Response>)(
      new Request("https://example.test/endpoint", { method: "POST", headers: {
        Authorization: "Bearer test", Origin: "https://example.test", "Content-Type": "application/json",
      }, body: JSON.stringify({ apiVersion: 999 }) }), deps);
    assertEquals(response.status, 400);
    assertEquals((await response.json()).code, "unsupported_api_version");
    assertEquals(unexpectedCalls, 0);
  });
}
