import {
  arrayValue,
  type JsonMap,
  mapValue,
  stringValue,
} from "./pomodoist_state.ts";
export type TaskDecompositionDeps = {
  env: Pick<typeof Deno.env, "get">;
  fetch: typeof fetch;
  now?: () => Date;
  deadline?: number;
};

export class TaskDecompositionError extends Error {
  constructor(
    readonly code: string,
    readonly status: number,
    message: string,
  ) {
    super(message);
  }
}

export const taskDecompositionPrompt = `
You turn a spoken Pomodoist transcript into separate quick-add tasks.
Return only JSON: {"tasks":[{"quickAdd":"task 1","description":"optional comment","subtasks":[{"quickAdd":"subtask"}]}]}.

Rules:
- Split into logical actionable tasks. If there is one task, return one item.
- Use subtasks only when the user explicitly describes child steps under a parent task.
- Correct only obvious gross typos. Do not rewrite style.
- Do not invent tasks, projects, labels, or times.
- Use the user's language for task titles.
- Put the actionable task title and Pomodoist tokens in quickAdd.
- Put extra context, notes, clarifications, and non-actionable details in description.
- Omit description or use null when there is no comment for the task.
- Preserve explicit #project, @label, p1-p4 priority, and focus estimates like 3p.
- Infer priority only when the user explicitly expresses importance, urgency, ranking, or low priority.
- Normalize spoken priorities to p1-p4 in quickAdd: p1 is critical/urgent/highest ("горит", "срочно", "обязательно первым"), p2 is important/high, p3 is normal/medium ("не срочно, но надо"), p4 is low/optional/backlog ("когда будет время", "можно потом", "низкий приоритет").
- Exact spoken ranks like "priority one" or "приоритет один" win over emotional wording.
- If there is no clear priority signal, omit priority. Do not add p4 by default.
- Interpret spoken dates and times in the transcript's language, including localized month names, AM/PM, and conversational phrases such as "half past five".
- Resolve dates and times against the supplied current local time. Treat numeric dates as day/month, never month/day.
- Emit every recognized date and time as YYYY-MM-DD and HH:mm scheduling tokens. If a date or time is ambiguous or cannot be determined, omit it rather than guess.
- Add scheduling tokens at the end using Pomodoist quick-add syntax: today, tomorrow, YYYY-MM-DD, HH:mm, 30m, 2h.
- For "distribute over 5 hours" style requests, spread tasks evenly inside that window.
- For "all day", use the waking day 09:00-22:00 unless the user gave another window.
- For "today", keep tasks on the current local date.
- For "this week" or "whole week", spread tasks across the next 7 calendar days.
- Use compact task strings. No Markdown, bullets, explanations, or keys other than quickAdd, description, subtasks.
`.trim();

export async function decomposeTranscript(
  command: JsonMap,
  deps: TaskDecompositionDeps,
  requestId: string,
) {
  const startedAt = performance.now();
  const transcript = stringValue(command.transcript)?.trim() ?? "";
  if (transcript.length === 0 || transcript.length > 20_000) {
    throw new TaskDecompositionError(
      "invalid_transcript",
      400,
      "Transcript must contain between 1 and 20000 characters.",
    );
  }
  const locale = stringValue(command.locale) ?? "";
  if (locale.length === 0 || locale.length > 35 || /[\r\n]/.test(locale)) {
    throw new TaskDecompositionError(
      "invalid_locale",
      400,
      "Locale must be a valid language tag.",
    );
  }
  if (command.smart != null && typeof command.smart !== "boolean") {
    throw new TaskDecompositionError(
      "invalid_smart_mode",
      400,
      "Smart mode must be a boolean.",
    );
  }
  const smart = command.smart === true;
  const currentLocalTime = stringValue(command.currentLocalTime) ??
    (deps.now?.() ?? new Date()).toISOString();
  if (
    currentLocalTime.length > 50 ||
    !Number.isFinite(Date.parse(currentLocalTime))
  ) {
    throw new TaskDecompositionError(
      "invalid_local_time",
      400,
      "Current local time must be an ISO-8601 timestamp.",
    );
  }

  // Finish before the client's 45s / 120s timeout, including fallback requests.
  const deadline = Math.min(
    startedAt + (smart ? 115_000 : 40_000),
    deps.deadline ?? Infinity,
  );
  const providers = [
    ...(!smart
      ? [
        {
          name: "cerebras",
          url: "https://api.cerebras.ai/v1/chat/completions",
          key: "CEREBRAS_API_KEY",
          timeoutMs: 8_000,
          options: {
            model: "gpt-oss-120b",
            reasoning_effort: "low",
            temperature: 0.1,
          },
        },
        {
          name: "openrouter",
          url: "https://openrouter.ai/api/v1/chat/completions",
          key: "POMODOIST_OPENROUTER_API_KEY",
          timeoutMs: 12_000,
          options: {
            model: "openai/gpt-oss-120b",
            reasoning: { effort: "low" },
            temperature: 0.1,
            provider: {
              sort: "latency",
              allow_fallbacks: true,
              require_parameters: true,
              // Cerebras has already failed; try independent providers.
              ignore: ["cerebras"],
            },
          },
        },
      ]
      : []),
    {
      name: "deepseek",
      url: "https://api.deepseek.com/chat/completions",
      key: "DEEPSEEK_API_KEY",
      timeoutMs: smart ? 115_000 : 40_000,
      options: {
        model: smart ? "deepseek-flash" : "deepseek-v4-flash",
        thinking: { type: smart ? "enabled" : "disabled" },
        ...(smart ? { reasoning_effort: "high" } : { temperature: 0.1 }),
      },
    },
  ];
  const requestBody = {
    response_format: { type: "json_object" },
    max_tokens: 4096,
    messages: [
      { role: "system", content: taskDecompositionPrompt },
      {
        role: "user",
        content:
          `Locale: ${locale}\nCurrent local time: ${currentLocalTime}\n\nTranscript:\n${transcript}`,
      },
    ],
  };
  let lastError = new TaskDecompositionError(
    "deepseek_not_configured",
    503,
    "No task analysis provider is configured.",
  );

  for (const provider of providers) {
    const apiKey = deps.env.get(provider.key)?.trim();
    if (!apiKey) continue;
    // Retry invalid JSON only at the last provider, within the same deadline.
    const attempts = provider.name === "deepseek" ? 2 : 1;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      const remainingMs = Math.floor(deadline - performance.now());
      if (remainingMs <= 0) {
        throw new TaskDecompositionError(
          `${provider.name}_timeout`,
          504,
          "Task analysis timed out.",
        );
      }
      try {
        const response = await deps.fetch(provider.url, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${apiKey}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({ ...requestBody, ...provider.options }),
          signal: AbortSignal.timeout(
            Math.min(provider.timeoutMs, remainingMs),
          ),
        });
        if (!response.ok) {
          await response.body?.cancel();
          throw new TaskDecompositionError(
            `${provider.name}_http_${response.status}`,
            502,
            "Task analysis provider request failed.",
          );
        }
        // Body reads must also complete within this attempt's timeout.
        const payload = await response.json();
        const choice = mapValue(arrayValue(mapValue(payload)?.choices)[0]);
        const content = stringValue(mapValue(choice?.message)?.content);
        const parsed = JSON.parse(content ?? "");
        const tasks = decodeTaskDrafts(mapValue(parsed)?.tasks ?? parsed);
        if (tasks.length === 0 || choice?.finish_reason === "length") {
          throw new SyntaxError("Invalid or truncated task JSON.");
        }
        console.info(JSON.stringify({
          requestId,
          smart,
          provider: provider.name,
          model: provider.options.model,
          stage: "complete",
          durationMs: Math.round(performance.now() - startedAt),
        }));
        return tasks;
      } catch (error) {
        const timedOut = error instanceof DOMException &&
          (error.name === "TimeoutError" || error.name === "AbortError");
        lastError = error instanceof TaskDecompositionError
          ? error
          : new TaskDecompositionError(
            `${provider.name}_${
              timedOut
                ? "timeout"
                : error instanceof SyntaxError
                ? "invalid_response"
                : "http_error"
            }`,
            timedOut ? 504 : 502,
            timedOut
              ? "Task analysis timed out."
              : "Task analysis provider returned an unusable response.",
          );
        console.warn(JSON.stringify({
          requestId,
          smart,
          provider: provider.name,
          stage: "provider_failed",
          code: lastError.code,
          durationMs: Math.round(performance.now() - startedAt),
        }));
        if (!lastError.code.endsWith("_invalid_response")) break;
      }
    }
  }
  throw lastError;
}

export function decodeTaskDrafts(value: unknown): JsonMap[] {
  return arrayValue(value)
    .map(decodeTaskDraft)
    .filter((draft): draft is JsonMap => draft != null);
}

export function decodeTaskDraft(value: unknown): JsonMap | null {
  const item = mapValue(value);
  if (item == null) return null;
  const quickAdd = stringValue(
    item.quickAdd ?? item.task ?? item.content ?? item.title,
  )?.trim();
  if (quickAdd == null || quickAdd.length === 0) return null;
  const description = stringValue(item.description ?? item.note)?.trim();
  const subtasks = decodeTaskDrafts(
    item.subtasks ?? item.subTasks ?? item.children ?? item.steps,
  );
  return {
    quickAdd,
    ...(description == null || description.length === 0 ? {} : { description }),
    ...(subtasks.length === 0 ? {} : { subtasks }),
  };
}
