import type { SupabaseClient } from "npm:@supabase/supabase-js@2";

import {
  pomodoistState,
  telegramCommandOps,
  telegramSnapshot,
} from "../pomodoist-watch/pomodoist_watch.ts";
import {
  TelegramError,
  type TelegramIdentity,
  type TelegramStore,
} from "./pomodoist_telegram.ts";

type JsonMap = Record<string, unknown>;

export function createTelegramStore(
  admin: SupabaseClient,
  webAppUrl: string,
): TelegramStore {
  async function identity(telegramUserId: string) {
    const { data, error } = await admin
      .from("pomodoist_telegram_accounts")
      .select("telegram_user_id,user_id,guest_user_id,client_id")
      .eq("telegram_user_id", telegramUserId)
      .maybeSingle();
    if (error) throw new Error(error.message);
    return data == null ? null : mapIdentity(data);
  }

  async function bootstrap(telegramUserId: string) {
    const guestKey = crypto.randomUUID();
    const created = await admin.auth.admin.createUser({
      email: `tg-${guestKey}@telegram.invalid`,
      email_confirm: true,
      app_metadata: { account_kind: "telegram_guest" },
    });
    if (created.error || created.data.user == null) {
      throw new Error(created.error?.message ?? "Guest bootstrap failed");
    }
    const guestUserId = created.data.user.id;
    const { data, error } = await admin.rpc("bootstrap_pomodoist_telegram", {
      p_telegram_user_id: telegramUserId,
      p_guest_user_id: guestUserId,
      p_client_id: crypto.randomUUID(),
    });
    if (error) {
      await deleteGuest(admin, guestUserId);
      throw new Error(error.message);
    }
    const mapped = mapIdentity(data as JsonMap);
    if (mapped.userId !== guestUserId) await deleteGuest(admin, guestUserId);
    return mapped;
  }

  async function loadState(userId: string) {
    const entities: unknown[] = [];
    for (let offset = 0;; offset += 1000) {
      const { data, error } = await admin
        .from("sync_entities")
        .select("entity_type,entity_id,server_revision,deleted_at,data")
        .eq("user_id", userId)
        .eq("app_id", "pomodoist")
        .order("server_revision")
        .range(offset, offset + 999);
      if (error) throw new Error(error.message);
      entities.push(...(data ?? []));
      if ((data?.length ?? 0) < 1000) break;
    }
    return pomodoistState(entities);
  }

  async function snapshot(account: TelegramIdentity, now: Date) {
    if (account.linked && account.guestUserId != null) {
      await deleteGuest(admin, account.guestUserId);
    }
    return {
      account: { linked: account.linked },
      ...telegramSnapshot(await loadState(account.userId), now),
    };
  }

  async function command(
    account: TelegramIdentity,
    value: JsonMap,
    now: Date,
  ) {
    const commandId = `${value.id ?? ""}`;
    let current = account;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const replay = await admin
        .from("sync_operation_receipts")
        .select("op_id")
        .eq("user_id", current.userId)
        .eq("op_id", commandId)
        .maybeSingle();
      if (replay.error) throw new Error(replay.error.message);
      if (replay.data != null) {
        return snapshot(await identity(current.telegramUserId) ?? current, now);
      }

      let operations;
      try {
        operations = telegramCommandOps(
          await loadState(current.userId),
          value,
          now,
        );
      } catch (error) {
        const refreshed = await identity(current.telegramUserId);
        if (refreshed != null && refreshed.userId !== current.userId) {
          current = refreshed;
          continue;
        }
        throw error;
      }
      if (operations.length === 0) {
        return snapshot(await identity(current.telegramUserId) ?? current, now);
      }

      const pushed = await admin.rpc("push_pomodoist_telegram_changes", {
        p_telegram_user_id: current.telegramUserId,
        p_expected_user_id: current.userId,
        p_client_id: current.clientId,
        p_operations: operations,
      });
      if (pushed.error == null) {
        return snapshot(await identity(current.telegramUserId) ?? current, now);
      }
      if (!pushed.error.message.includes("Telegram mapping changed")) {
        if (pushed.error.message.includes("Telegram Focus already active")) {
          throw new TelegramError("focus_already_active", 409);
        }
        throw new Error(pushed.error.message);
      }
      const refreshed = await identity(current.telegramUserId);
      if (refreshed == null || refreshed.userId === current.userId) break;
      current = refreshed;
    }
    throw new TelegramError("retry_later", 409);
  }

  async function beginLink(account: TelegramIdentity, now: Date) {
    if (account.linked) throw new TelegramError("already_linked", 409);
    const tokenBytes = crypto.getRandomValues(new Uint8Array(32));
    const token = base64Url(tokenBytes);
    const tokenHash = new Uint8Array(
      await crypto.subtle.digest("SHA-256", tokenBytes.buffer as ArrayBuffer),
    );
    const linked = await admin.rpc("begin_pomodoist_telegram_link", {
      p_telegram_user_id: account.telegramUserId,
      p_token_hash: `\\x${hex(tokenHash)}`,
      p_expires_at: new Date(now.getTime() + 15 * 60 * 1000).toISOString(),
    });
    if (linked.error) throw new Error(linked.error.message);
    return {
      url: `${webAppUrl}/telegram-account-link?token=${
        encodeURIComponent(token)
      }`,
    };
  }

  async function completeLink(
    token: string,
    authorization: string,
    _now: Date,
  ) {
    const match = /^Bearer\s+(.+)$/i.exec(authorization);
    if (match == null) throw new TelegramError("authorization_required", 401);
    const authenticated = await admin.auth.getUser(match[1]);
    if (authenticated.error || authenticated.data.user == null) {
      throw new TelegramError("authorization_invalid", 401);
    }
    let tokenBytes: Uint8Array;
    try {
      tokenBytes = decodeBase64Url(token);
    } catch {
      throw new TelegramError("invalid_link_token", 400);
    }
    if (tokenBytes.length !== 32) {
      throw new TelegramError("invalid_link_token", 400);
    }
    const tokenHash = new Uint8Array(
      await crypto.subtle.digest("SHA-256", tokenBytes.buffer as ArrayBuffer),
    );
    const completed = await admin.rpc("complete_pomodoist_telegram_link", {
      p_token_hash: `\\x${hex(tokenHash)}`,
      p_target_user_id: authenticated.data.user.id,
    });
    if (completed.error) {
      if (completed.error.message.includes("merge conflict")) {
        throw new TelegramError("link_conflict", 409);
      }
      if (completed.error.message.includes("expired Telegram link token")) {
        throw new TelegramError("link_expired", 410);
      }
      throw new Error(completed.error.message);
    }
    const result = completed.data as JsonMap;
    const guestUserId = stringValue(result.guestUserId);
    if (guestUserId != null) await deleteGuest(admin, guestUserId);
    return { linked: true, email: authenticated.data.user.email ?? null };
  }

  return { identity, bootstrap, snapshot, command, beginLink, completeLink };
}

async function deleteGuest(admin: SupabaseClient, userId: string) {
  const found = await admin.auth.admin.getUserById(userId);
  const user = found.data.user;
  if (
    found.error ||
    user == null ||
    user.app_metadata?.account_kind !== "telegram_guest" ||
    !user.email?.endsWith("@telegram.invalid")
  ) {
    return false;
  }
  const deleted = await admin.auth.admin.deleteUser(userId);
  return deleted.error == null;
}

function mapIdentity(value: JsonMap): TelegramIdentity {
  const telegramUserId = required(
    value.telegramUserId ?? value.telegram_user_id,
  );
  const userId = required(value.userId ?? value.user_id);
  const guestUserId = stringValue(value.guestUserId ?? value.guest_user_id);
  return {
    telegramUserId,
    userId,
    guestUserId,
    clientId: required(value.clientId ?? value.client_id),
    linked: value.linked === true || guestUserId == null ||
      userId !== guestUserId,
  };
}

function required(value: unknown) {
  const result = stringValue(value);
  if (result == null || result.length === 0) {
    throw new Error("Invalid Telegram mapping");
  }
  return result;
}

function stringValue(value: unknown) {
  return typeof value === "string" || typeof value === "number"
    ? `${value}`
    : undefined;
}

function base64Url(value: Uint8Array) {
  return btoa(String.fromCharCode(...value))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function decodeBase64Url(value: string) {
  const normalized = value.replaceAll("-", "+").replaceAll("_", "/");
  const decoded = atob(
    normalized.padEnd(Math.ceil(normalized.length / 4) * 4, "="),
  );
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

function hex(value: Uint8Array) {
  return [...value].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
