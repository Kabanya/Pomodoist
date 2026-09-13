export type LlmQuotaSubject = { userId: string } | { purchaseSubject: string };
export type LlmQuota = (
  action: "reserve" | "complete" | "release",
  subject: LlmQuotaSubject,
  requestId: string,
) => Promise<{ allowed: boolean; resetsAt?: string }>;

export function createLlmQuota(
  env: Pick<typeof Deno.env, "get">,
  fetcher: typeof fetch = fetch,
): LlmQuota {
  return async (action, subject, requestId) => {
    const url = env.get("SUPABASE_URL");
    const key = env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !key) throw new Error("Quota unavailable");
    // Retrying with the same request ID cannot reserve or charge twice.
    for (let attempt = 0; attempt < 2; attempt++) {
      try {
        const response = await fetcher(
          `${url}/rest/v1/rpc/pomodoist_llm_quota`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${key}`,
              apikey: key,
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              p_action: action,
              p_user_id: "userId" in subject ? subject.userId : null,
              p_purchase_subject: "purchaseSubject" in subject
                ? subject.purchaseSubject
                : null,
              p_request_id: requestId,
            }),
            signal: AbortSignal.timeout(5000),
          },
        );
        if (!response.ok) {
          await response.body?.cancel();
          throw new Error("Quota unavailable");
        }
        const data = await response.json();
        if (typeof data?.allowed !== "boolean") {
          throw new Error("Quota unavailable");
        }
        return { allowed: data.allowed, resetsAt: data.resetsAt };
      } catch {
        if (attempt === 1) throw new Error("Quota unavailable");
      }
    }
    throw new Error("Quota unavailable");
  };
}
