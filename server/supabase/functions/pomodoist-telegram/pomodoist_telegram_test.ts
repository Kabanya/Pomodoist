import { assertEquals, assertRejects } from "jsr:@std/assert";

import {
  handlePomodoistTelegram,
  type TelegramIdentity,
  type TelegramStore,
  verifyTelegramInitData,
} from "./pomodoist_telegram.ts";
import { createTelegramStore } from "./store.ts";
import {
  pomodoistState,
  telegramCommandOps,
  telegramSnapshot,
} from "../pomodoist-watch/pomodoist_watch.ts";

const botToken = "123456:test-token";
const now = new Date("2026-08-03T12:00:00.000Z");

Deno.test("Telegram initData accepts a valid signature", async () => {
  const initData = await signedInitData(botToken, 42, now);
  assertEquals(
    await verifyTelegramInitData(initData, botToken, now),
    { userId: "42", authDate: Math.floor(now.getTime() / 1000) },
  );
});

Deno.test("Telegram initData rejects tampering, expiry, and another bot", async () => {
  const valid = await signedInitData(botToken, 42, now);
  await assertRejects(
    () =>
      verifyTelegramInitData(
        valid.replace("%22id%22%3A42", "%22id%22%3A43"),
        botToken,
        now,
      ),
    Error,
    "invalid_init_data",
  );
  await assertRejects(
    () => verifyTelegramInitData(valid, "999999:other-token", now),
    Error,
    "invalid_init_data",
  );
  const stale = await signedInitData(
    botToken,
    42,
    new Date(now.getTime() - 3_601_000),
  );
  await assertRejects(
    () => verifyTelegramInitData(stale, botToken, now),
    Error,
    "expired_init_data",
  );
});

Deno.test("handler bootstraps once and isolates Telegram users", async () => {
  const store = new MemoryStore();
  const deps = {
    botToken,
    allowedOrigin: "https://app.pomodoist.com",
    now: () => now,
    store,
  };
  const [first, second] = await Promise.all([
    handlePomodoistTelegram(await request("snapshot", 42), deps),
    handlePomodoistTelegram(await request("snapshot", 42), deps),
  ]);
  const other = await handlePomodoistTelegram(
    await request("snapshot", 43),
    deps,
  );

  assertEquals(first.status, 200);
  assertEquals(second.status, 200);
  assertEquals(other.status, 200);
  assertEquals(store.bootstraps.get("42"), 1);
  assertEquals(store.bootstraps.get("43"), 1);
  assertEquals(store.snapshotUsers, ["guest-42", "guest-42", "guest-43"]);
});

Deno.test("handler forwards the client command UUID for idempotent replay", async () => {
  const store = new MemoryStore();
  const deps = {
    botToken,
    allowedOrigin: "https://app.pomodoist.com",
    now: () => now,
    store,
  };
  const command = {
    type: "task.create",
    id: "11111111-1111-4111-8111-111111111111",
    content: "Ship Telegram MVP",
  };
  const first = await handlePomodoistTelegram(
    await request("command", 42, { command }),
    deps,
  );
  const replay = await handlePomodoistTelegram(
    await request("command", 42, { command }),
    deps,
  );

  assertEquals(first.status, 200);
  assertEquals(replay.status, 200);
  assertEquals(store.commands.map((item) => item.command.id), [
    command.id,
    command.id,
  ]);
  assertEquals(
    store.commands.every((item) => item.identity.userId === "guest-42"),
    true,
  );
});

Deno.test("handler signs out a linked Telegram account into its new guest", async () => {
  const store = new MemoryStore();
  store.identities.set("42", {
    telegramUserId: "42",
    userId: "account-42",
    guestUserId: "old-guest-42",
    clientId: "11111111-1111-4111-8111-000000000042",
    linked: true,
  });
  const response = await handlePomodoistTelegram(
    await request("unlink_account", 42, {
      view: "inbox",
      page: 0,
      timeZone: "Europe/Moscow",
    }),
    {
      botToken,
      allowedOrigin: "https://app.pomodoist.com",
      now: () => now,
      store,
    },
  );

  assertEquals(response.status, 200);
  assertEquals(store.unlinks, ["account-42"]);
  assertEquals((await response.json()).data, {
    account: { linked: false },
    inbox: [],
    focus: null,
  });
});

Deno.test("standalone Focus crosses the signed handler, store, and runtime and survives refresh", async () => {
  let revision = 0;
  const rows: Record<string, unknown>[] = [];
  const mapping = {
    telegram_user_id: "42",
    user_id: "guest-42",
    guest_user_id: "guest-42",
    client_id: "11111111-1111-4111-8111-000000000042",
  };
  const admin = {
    from(table: string) {
      const builder = {
        select: () => builder,
        eq: () => builder,
        is: () => builder,
        in: () => builder,
        gt: () => builder,
        order: () => builder,
        limit: async () => ({ data: rows, error: null }),
        maybeSingle: async () => ({
          data: table === "pomodoist_telegram_accounts" ? mapping : null,
          error: null,
        }),
      };
      return builder;
    },
    rpc: async (_name: string, args: Record<string, unknown>) => {
      for (const operation of args.p_operations as Record<string, unknown>[]) {
        rows.push({
          entity_type: operation.entityType,
          entity_id: operation.entityId,
          server_revision: ++revision,
          deleted_at: null,
          data: operation.payload,
        });
      }
      return { data: {}, error: null };
    },
    channel: () => ({ send: async () => "ok" }),
    removeChannel: async () => "ok",
  };
  const store = createTelegramStore(
    admin as unknown as Parameters<typeof createTelegramStore>[0],
    "https://app.pomodoist.com",
    { pomodoistState, telegramCommandOps, telegramSnapshot },
  );
  const deps = {
    botToken,
    allowedOrigin: "https://app.pomodoist.com",
    now: () => now,
    store,
  };
  const command = await handlePomodoistTelegram(
    await request("command", 42, {
      command: {
        type: "focus.start",
        id: "22222222-2222-4222-8222-222222222222",
      },
    }),
    deps,
  );
  const started = (await command.json()).data;
  const refreshed = await handlePomodoistTelegram(
    await request("snapshot", 42),
    deps,
  );
  const reloaded = (await refreshed.json()).data;

  assertEquals(command.status, 200);
  assertEquals(started.focus.run.taskId, null);
  assertEquals(reloaded.focus.run.id, started.focus.run.id);
  assertEquals(reloaded.focus.interval.status, "running");
});

Deno.test("handler rejects non-Telegram access and disallowed origins", async () => {
  const deps = {
    botToken,
    allowedOrigin: "https://app.pomodoist.com",
    now: () => now,
    store: new MemoryStore(),
  };
  const missing = new Request(
    "https://edge.example/functions/v1/pomodoist-telegram",
    {
      method: "POST",
      headers: {
        Origin: deps.allowedOrigin,
        "content-type": "application/json",
      },
      body: JSON.stringify({ action: "snapshot" }),
    },
  );
  const foreign = await request("snapshot", 42);
  const foreignHeaders = new Headers(foreign.headers);
  foreignHeaders.set("Origin", "https://evil.example");

  assertEquals((await handlePomodoistTelegram(missing, deps)).status, 401);
  assertEquals(
    (await handlePomodoistTelegram(
      new Request(foreign, { headers: foreignHeaders }),
      deps,
    )).status,
    403,
  );
});

Deno.test("local config disables gateway JWT verification for Telegram", async () => {
  const config = await Deno.readTextFile(
    new URL("../../config.toml", import.meta.url),
  );
  assertEquals(
    /\[functions\.pomodoist-telegram\]\s+verify_jwt = false/.test(config),
    true,
  );
});

async function request(
  action: string,
  telegramUserId: number,
  extra: Record<string, unknown> = {},
) {
  return new Request("https://edge.example/functions/v1/pomodoist-telegram", {
    method: "POST",
    headers: {
      Origin: "https://app.pomodoist.com",
      "content-type": "application/json",
      "X-Telegram-Init-Data": await signedInitData(
        botToken,
        telegramUserId,
        now,
      ),
    },
    body: JSON.stringify({ action, ...extra }),
  });
}

async function signedInitData(token: string, userId: number, at: Date) {
  const params = new URLSearchParams({
    auth_date: `${Math.floor(at.getTime() / 1000)}`,
    query_id: "AAHdF6IQAAAAAN0XohDhrOrc",
    user: JSON.stringify({ id: userId, language_code: "en" }),
  });
  const checkString = [...params.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  const secret = await crypto.subtle.sign(
    "HMAC",
    await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode("WebAppData"),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    ),
    new TextEncoder().encode(token),
  );
  const hash = await crypto.subtle.sign(
    "HMAC",
    await crypto.subtle.importKey(
      "raw",
      secret,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    ),
    new TextEncoder().encode(checkString),
  );
  params.set(
    "hash",
    [...new Uint8Array(hash)].map((byte) => byte.toString(16).padStart(2, "0"))
      .join(""),
  );
  return params.toString();
}

class MemoryStore implements TelegramStore {
  identities = new Map<string, TelegramIdentity>();
  bootstraps = new Map<string, number>();
  snapshotUsers: string[] = [];
  commands: Array<
    { identity: TelegramIdentity; command: Record<string, unknown> }
  > = [];
  unlinks: string[] = [];

  async identity(telegramUserId: string) {
    return this.identities.get(telegramUserId) ?? null;
  }

  async bootstrap(telegramUserId: string) {
    const existing = this.identities.get(telegramUserId);
    if (existing) return existing;
    const identity = {
      telegramUserId,
      userId: `guest-${telegramUserId}`,
      clientId: `11111111-1111-4111-8111-${telegramUserId.padStart(12, "0")}`,
      linked: false,
    };
    this.identities.set(telegramUserId, identity);
    this.bootstraps.set(
      telegramUserId,
      (this.bootstraps.get(telegramUserId) ?? 0) + 1,
    );
    return identity;
  }

  async snapshot(identity: TelegramIdentity) {
    this.snapshotUsers.push(identity.userId);
    return { account: { linked: identity.linked }, inbox: [], focus: null };
  }

  async command(identity: TelegramIdentity, command: Record<string, unknown>) {
    this.commands.push({ identity, command });
    return this.snapshot(identity);
  }

  async beginLink() {
    return { token: "link-token" };
  }

  async unlinkAccount(identity: TelegramIdentity) {
    this.unlinks.push(identity.userId);
    const guest = { ...identity, userId: `guest-${identity.telegramUserId}`, guestUserId: `guest-${identity.telegramUserId}`, linked: false };
    this.identities.set(identity.telegramUserId, guest);
    return this.snapshot(guest);
  }

  async completeLink() {
    return { linked: true };
  }
}
