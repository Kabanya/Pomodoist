/** Versioning applies only to Pomodoist-owned JSON envelopes, never webhooks. */
export function apiVersionError(body: unknown) {
  if (!body || typeof body !== "object" || Array.isArray(body) || !("apiVersion" in body)) return null;
  return body.apiVersion === 0 || body.apiVersion === 1 ? null : {
    code: "unsupported_api_version", error: "Unsupported Pomodoist API version.",
  };
}
