import {
  type AppleStoreTransaction,
  verifyAppleStoreTransactionJws,
} from "./apple_app_transaction.ts";
import {
  pomodoistAppleVerificationOptions,
  pomodoistPurchaseState,
} from "./pomodoist_storekit.ts";

import {
  type JsonMap,
  mapValue,
  type SupabaseClient,
  type User,
} from "./pomodoist_state.ts";
import {
  decomposeTranscript,
  TaskDecompositionError,
} from "./task_decomposition.ts";
import type { LlmQuota, LlmQuotaSubject } from "./llm_quota.ts";

async function activePurchaseSubject(
  body: JsonMap,
  deps: PomodoistWatchDeps,
  now: Date,
) {
  const values = body.storeTransactions;
  if (!Array.isArray(values) || values.length === 0 || values.length > 100) {
    return null;
  }
  const verify = deps.verifyStoreTransaction ?? verifyAppleStoreTransactionJws;
  for (const value of values) {
    if (
      typeof value !== "string" || value.length === 0 || value.length > 32768
    ) {
      continue;
    }
    try {
      const transaction = await verify(
        value,
        pomodoistAppleVerificationOptions,
      );
      if (pomodoistPurchaseState(transaction, now)?.status === "active") {
        // Renewals and re-signed receipts retain the same original purchase ID.
        if (!/^[^:]{1,128}$/.test(transaction.originalTransactionId)) continue;
        return `apple:${transaction.environment}:${transaction.originalTransactionId}`;
      }
    } catch {
      // A candidate may be stale or unrelated; another signed transaction can
      // still represent the customer's current entitlement.
    }
  }
  return null;
}

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

export type PomodoistWatchDeps = {
  env: Pick<typeof Deno.env, "get">;
  fetch: typeof fetch;
  createClient: (authorization: string) => SupabaseClient;
  now?: () => Date;
  uuid?: () => string;
  quota?: LlmQuota;
  verifyStoreTransaction?: (
    jws: string,
    options: typeof pomodoistAppleVerificationOptions,
  ) => Promise<AppleStoreTransaction>;
};

export async function readJson(req: Request): Promise<JsonMap | null> {
  try {
    return mapValue(await req.json());
  } catch {
    return null;
  }
}

export function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

export async function handleTaskDecomposition(
  body: JsonMap,
  command: JsonMap,
  user: User | null,
  deps: PomodoistWatchDeps,
  now: Date,
) {
  const uuid = deps.uuid ?? (() => crypto.randomUUID());
  const subject: LlmQuotaSubject | null =
    user && !(user as User & { is_anonymous?: boolean }).is_anonymous
      ? { userId: user.id }
      : await activePurchaseSubject(body, deps, now).then((purchaseSubject) =>
        purchaseSubject ? { purchaseSubject } : null
      );
  if (!subject) {
    return json({
      ok: false,
      code: "purchase_verification_failed",
      error: "Could not verify Pomodoist Pro purchase.",
    }, 403);
  }
  const requestId = uuid();
  const startedAt = performance.now();
  const unavailable = () =>
    json({
      ok: false,
      code: "llm_quota_unavailable",
      error: "Task analysis usage verification is temporarily unavailable.",
      retryable: true,
    }, 503);
  let reservation;
  try {
    if (!deps.quota) return unavailable();
    reservation = await deps.quota("reserve", subject, requestId);
  } catch {
    return unavailable();
  }
  if (!reservation.allowed) {
    return json({
      ok: false,
      code: "llm_quota_exceeded",
      error: "Monthly task analysis limit reached.",
      retryable: false,
      resetsAt: reservation.resetsAt,
    }, 429);
  }
  let tasks;
  try {
    tasks = await decomposeTranscript(command, {
      ...deps,
      // Include reservation time and leave ten seconds for quota settlement.
      deadline: startedAt + (command.smart === true ? 105_000 : 30_000),
    }, requestId);
  } catch (error) {
    try {
      await deps.quota("release", subject, requestId);
    } catch { /* expiry releases it */ }
    if (error instanceof TaskDecompositionError) {
      console.error(JSON.stringify({
        requestId,
        smart: command.smart === true,
        stage: error.code.startsWith("invalid_") ? "validation" : "provider",
        durationMs: Math.round(performance.now() - startedAt),
        code: error.code,
      }));
      return json(
        { ok: false, code: error.code, error: error.message },
        error.status,
      );
    }
    return json(
      {
        ok: false,
        code: "task_decomposition_failed",
        error: "Task analysis failed.",
      },
      502,
    );
  }
  try {
    await deps.quota("complete", subject, requestId);
  } catch {
    return unavailable();
  }
  return json({ ok: true, tasks });
}
