import { strict as assert } from "node:assert";
import {
  type CalendarActionDeps,
  handleCalendarActions,
} from "../_shared/calendar/actions.ts";
const captured: Record<string, unknown>[] = [];
const dependencies = (): CalendarActionDeps => ({
  provider: "outlook",
  clientId: "client",
  configured: true,
  redirectUri: "https://api.test/calendar",
  appRedirectUri: "pomodoist://outlook-calendar-connected",
  authenticate: async () => "user",
  storeState: async (value) => {
    captured.push(value);
  },
  consumeState: async () => ({ userId: "user", verifier: "verifier" }),
  exchange: async () => ({
    refreshToken: "refresh",
    accessToken: "access",
    accountId: "microsoft-user",
    accountEmail: "me@example.test",
  }),
  connect: async () => {},
  sync: async () => {},
  disconnect: async () => {},
});
Deno.test("Microsoft authorization uses PKCE offline access and delegated calendars", async () => {
  const response = await handleCalendarActions(
    new Request("https://api.test/calendar", {
      method: "POST",
      headers: { Authorization: "Bearer user" },
      body: JSON.stringify({ action: "start" }),
    }),
    dependencies(),
  );
  const url = new URL((await response.json()).authorizationUrl);
  assert.equal(url.hostname, "login.microsoftonline.com");
  assert.equal(url.searchParams.get("code_challenge_method"), "S256");
  assert.match(url.searchParams.get("scope")!, /Calendars.ReadWrite/);
  assert.match(url.searchParams.get("scope")!, /offline_access/);
  assert.notEqual(captured.at(-1)?.stateHash, url.searchParams.get("state"));
});
Deno.test("replayed OAuth state cannot connect an account", async () => {
  const deps = dependencies();
  let connected = false;
  deps.consumeState = async () => null;
  deps.connect = async () => {
    connected = true;
  };
  const response = await handleCalendarActions(
    new Request("https://api.test/calendar?code=code&state=state"),
    deps,
  );
  assert.equal(response.status, 400);
  assert.equal(connected, false);
});
Deno.test("OAuth callback binds provider identity to the stored Pomodoist user", async () => {
  const deps = dependencies();
  let bound: unknown;
  deps.connect = async (user, tokens) => {
    bound = [user, tokens.accountId];
  };
  const response = await handleCalendarActions(
    new Request("https://api.test/calendar?code=code&state=state"),
    deps,
  );
  assert.equal(response.status, 302);
  assert.deepEqual(bound, ["user", "microsoft-user"]);
});
Deno.test("unauthenticated calendar actions are rejected", async () => {
  const deps = dependencies();
  deps.authenticate = async () => null;
  const response = await handleCalendarActions(
    new Request("https://api.test/calendar", {
      method: "POST",
      body: '{"action":"disconnect"}',
    }),
    deps,
  );
  assert.equal(response.status, 401);
});
