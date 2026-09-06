type JsonMap = Record<string, unknown>;

export type TelegramIdentity = {
  telegramUserId: string;
  userId: string;
  guestUserId?: string;
  clientId: string;
  linked: boolean;
};

export type TelegramStore = {
  identity: (telegramUserId: string) => Promise<TelegramIdentity | null>;
  bootstrap: (telegramUserId: string) => Promise<TelegramIdentity>;
  snapshot: (identity: TelegramIdentity, now: Date) => Promise<unknown>;
  command: (
    identity: TelegramIdentity,
    command: JsonMap,
    now: Date,
  ) => Promise<unknown>;
  beginLink: (identity: TelegramIdentity, now: Date) => Promise<unknown>;
  completeLink: (
    token: string,
    authorization: string,
    now: Date,
  ) => Promise<unknown>;
};

export type PomodoistTelegramDeps = {
  botToken: string;
  allowedOrigin: string;
  store: TelegramStore;
  now?: () => Date;
};

export async function handlePomodoistTelegram(
  req: Request,
  deps: PomodoistTelegramDeps,
) {
  const origin = req.headers.get("Origin") ?? "";
  if (origin !== deps.allowedOrigin) {
    return response({ ok: false, code: "origin_forbidden" }, 403, origin, deps);
  }
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors(origin) });
  }
  if (req.method !== "POST") {
    return response(
      { ok: false, code: "method_not_allowed" },
      405,
      origin,
      deps,
    );
  }
  if (Number(req.headers.get("Content-Length") ?? "0") > 16_384) {
    return response({ ok: false, code: "body_too_large" }, 413, origin, deps);
  }

  let body: JsonMap;
  try {
    const text = await req.text();
    if (text.length > 16_384) throw new TelegramError("body_too_large", 413);
    const value = JSON.parse(text);
    if (value == null || typeof value !== "object" || Array.isArray(value)) {
      throw new Error();
    }
    body = value as JsonMap;
  } catch (error) {
    const failure = error instanceof TelegramError
      ? error
      : new TelegramError("invalid_body", 400);
    return response(
      { ok: false, code: failure.code },
      failure.status,
      origin,
      deps,
    );
  }

  const action = stringValue(body.action);
  const now = deps.now?.() ?? new Date();
  try {
    if (action === "complete_link") {
      const token = requiredString(body.token, "invalid_link_token", 400, 512);
      const authorization = requiredString(
        req.headers.get("Authorization"),
        "authorization_required",
        401,
        8192,
      );
      return response(
        {
          ok: true,
          data: await deps.store.completeLink(token, authorization, now),
        },
        200,
        origin,
        deps,
      );
    }

    const initData = requiredString(
      req.headers.get("X-Telegram-Init-Data"),
      "telegram_context_required",
      401,
      8192,
    );
    const verified = await verifyTelegramInitData(
      initData,
      deps.botToken,
      now,
    );
    const identity = await deps.store.identity(verified.userId) ??
      await deps.store.bootstrap(verified.userId);

    let data: unknown;
    if (action === "snapshot") {
      data = await deps.store.snapshot(identity, now);
    } else if (action === "command") {
      const command = mapValue(body.command);
      validateCommand(command);
      data = await deps.store.command(identity, command!, now);
    } else if (action === "begin_link") {
      data = await deps.store.beginLink(identity, now);
    } else {
      throw new TelegramError("unsupported_action", 400);
    }
    return response({ ok: true, data }, 200, origin, deps);
  } catch (error) {
    const failure = error instanceof TelegramError
      ? error
      : new TelegramError("request_failed", 400);
    return response(
      { ok: false, code: failure.code },
      failure.status,
      origin,
      deps,
    );
  }
}

export async function verifyTelegramInitData(
  initData: string,
  botToken: string,
  now = new Date(),
) {
  if (
    initData.length === 0 || initData.length > 8192 || botToken.length === 0
  ) {
    throw new TelegramError("invalid_init_data", 401);
  }
  const params = new URLSearchParams(initData);
  const hash = params.get("hash") ?? "";
  params.delete("hash");
  if (!/^[a-f0-9]{64}$/i.test(hash)) {
    throw new TelegramError("invalid_init_data", 401);
  }
  const checkString = [...params.entries()]
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  const secret = await hmac(
    new TextEncoder().encode("WebAppData"),
    new TextEncoder().encode(botToken),
  );
  const expected = await hmac(secret, new TextEncoder().encode(checkString));
  if (!constantTimeEqual(hex(expected), hash.toLowerCase())) {
    throw new TelegramError("invalid_init_data", 401);
  }

  const authDate = Number(params.get("auth_date"));
  const nowSeconds = Math.floor(now.getTime() / 1000);
  if (!Number.isInteger(authDate) || authDate > nowSeconds + 30) {
    throw new TelegramError("invalid_init_data", 401);
  }
  if (nowSeconds - authDate > 3600) {
    throw new TelegramError("expired_init_data", 401);
  }
  let user: JsonMap | null = null;
  try {
    user = mapValue(JSON.parse(params.get("user") ?? ""));
  } catch {
    // handled below
  }
  const userId = user?.id;
  if (
    (typeof userId !== "number" && typeof userId !== "string") ||
    !/^\d{1,20}$/.test(`${userId}`)
  ) {
    throw new TelegramError("invalid_init_data", 401);
  }
  return { userId: `${userId}`, authDate };
}

const commandTypes = new Set([
  "task.create",
  "task.complete",
  "task.uncomplete",
  "focus.start",
  "focus.pause",
  "focus.resume",
  "focus.stop",
  "focus.complete",
]);

function validateCommand(command: JsonMap | null) {
  if (command == null || !commandTypes.has(stringValue(command.type) ?? "")) {
    throw new TelegramError("unsupported_command", 400);
  }
  const id = requiredString(command.id, "invalid_command_id", 400, 64);
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
      .test(id)
  ) {
    throw new TelegramError("invalid_command_id", 400);
  }
  if (command.type === "task.create") {
    const content = requiredString(
      command.content,
      "invalid_task_content",
      400,
      2000,
    );
    if (content.trim().length === 0) {
      throw new TelegramError("invalid_task_content", 400);
    }
  }
  if (
    command.type === "task.complete" ||
    command.type === "task.uncomplete" ||
    command.type === "focus.start"
  ) {
    const taskId = requiredString(
      command.taskId,
      "invalid_task_id",
      400,
      64,
    );
    if (!/^[0-9a-f-]{36}$/i.test(taskId)) {
      throw new TelegramError("invalid_task_id", 400);
    }
  }
}

async function hmac(key: BufferSource, value: BufferSource) {
  return new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      await crypto.subtle.importKey(
        "raw",
        key,
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"],
      ),
      value,
    ),
  );
}

function hex(value: Uint8Array) {
  return [...value].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string) {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

function requiredString(
  value: unknown,
  code: string,
  status: number,
  maximum: number,
) {
  if (
    typeof value !== "string" || value.length === 0 || value.length > maximum
  ) {
    throw new TelegramError(code, status);
  }
  return value;
}

function stringValue(value: unknown) {
  return typeof value === "string" ? value : undefined;
}

function mapValue(value: unknown): JsonMap | null {
  return value != null && typeof value === "object" && !Array.isArray(value)
    ? value as JsonMap
    : null;
}

export class TelegramError extends Error {
  constructor(readonly code: string, readonly status: number) {
    super(code);
  }
}

function cors(origin: string) {
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers":
      "authorization, apikey, content-type, x-client-info, x-telegram-init-data",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

function response(
  body: unknown,
  status: number,
  origin: string,
  deps: PomodoistTelegramDeps,
) {
  return Response.json(body, {
    status,
    headers: origin === deps.allowedOrigin
      ? cors(origin)
      : { "Vary": "Origin" },
  });
}
