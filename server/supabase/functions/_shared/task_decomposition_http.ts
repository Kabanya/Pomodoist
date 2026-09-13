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

export async function hasActivePomodoistStoreTransaction(
  body: JsonMap,
  deps: PomodoistWatchDeps,
  now: Date,
) {
  const values = body.storeTransactions;
  if (!Array.isArray(values) || values.length === 0 || values.length > 100) {
    return false;
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
        return true;
      }
    } catch {
      // A candidate may be stale or unrelated; another signed transaction can
      // still represent the customer's current entitlement.
    }
  }
  return false;
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
  if (!user && !(await hasActivePomodoistStoreTransaction(body, deps, now))) {
    return json({
      ok: false,
      code: "purchase_verification_failed",
      error: "Could not verify Pomodoist Pro purchase.",
    }, 403);
  }
  const requestId = uuid();
  const startedAt = performance.now();
  try {
    const tasks = await decomposeTranscript(command, deps, requestId);
    return json({ ok: true, tasks });
  } catch (error) {
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
}
