import { strict as assert } from "node:assert";
import { CalendarTokenClient } from "./tokens.ts";
Deno.test("Microsoft code exchange uses PKCE and resolves identity from authenticated Graph", async () => {
  const calls: string[] = [];
  const client = new CalendarTokenClient(
    "outlook",
    "id",
    "secret",
    "https://api.test/callback",
    async (url, init) => {
      calls.push(String(url));
      if (calls.length === 1) {
        assert.match(String(init?.body), /code_verifier=verifier/);
        return Response.json({
          access_token: "access",
          refresh_token: "refresh",
        });
      }
      assert.equal(
        new Headers(init?.headers).get("Authorization"),
        "Bearer access",
      );
      return Response.json({ id: "account", mail: "me@example.test" });
    },
  );
  const result = await client.exchange("code", "verifier");
  assert.equal(result.accountId, "account");
  assert.equal(result.refreshToken, "refresh");
});
Deno.test("refresh persists rotated token and does not repeat identity reads", async () => {
  let calls = 0;
  const client = new CalendarTokenClient(
    "outlook",
    "id",
    "secret",
    "https://api.test/callback",
    async () => {
      calls++;
      return Response.json({
        access_token: "access",
        refresh_token: "rotated",
      });
    },
  );
  const result = await client.refresh("old");
  assert.equal(result.refreshToken, "rotated");
  assert.equal(calls, 1);
});
