export async function readLimitedJson(
  req: Request,
  maxBytes: number,
): Promise<
  | { ok: true; value: unknown }
  | { ok: false; error: string; status: number }
> {
  const declaredLength = Number(req.headers.get("Content-Length"));
  if (Number.isFinite(declaredLength) && declaredLength > maxBytes) {
    return { ok: false, error: "Request body is too large.", status: 413 };
  }
  if (req.body == null) {
    return invalidJson();
  }

  const chunks: Uint8Array[] = [];
  const reader = req.body.getReader();
  let length = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > maxBytes) {
      await reader.cancel();
      return { ok: false, error: "Request body is too large.", status: 413 };
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.length;
  }
  try {
    return {
      ok: true,
      value: JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      ),
    };
  } catch {
    return invalidJson();
  }
}

function invalidJson() {
  return {
    ok: false as const,
    error: "Request body must be valid JSON.",
    status: 400,
  };
}
