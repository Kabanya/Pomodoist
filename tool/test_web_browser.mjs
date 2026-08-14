#!/usr/bin/env node

import { constants } from "node:fs";
import { access, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn } from "node:child_process";

const targetUrl = process.argv[2];
if (!targetUrl) {
  console.error("Usage: test_web_browser.mjs <app-url>");
  process.exit(2);
}

const chromeCandidates = [
  process.env.CHROME_BIN,
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/bin/google-chrome",
  "/usr/bin/google-chrome-stable",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
].filter(Boolean);

let chromePath;
for (const candidate of chromeCandidates) {
  try {
    await access(candidate, constants.X_OK);
    chromePath = candidate;
    break;
  } catch (_) {
    // Keep looking for a usable browser.
  }
}

if (!chromePath) {
  console.error(
    "ERROR: Chrome/Chromium is required; set CHROME_BIN in this environment.",
  );
  process.exit(1);
}

const profile = await mkdtemp(join(tmpdir(), "pomodoist-chrome-"));
const chrome = spawn(
  chromePath,
  [
    "--headless=new",
    "--remote-debugging-port=0",
    `--user-data-dir=${profile}`,
    "--no-first-run",
    "--no-default-browser-check",
    "--disable-background-networking",
    "--disable-component-update",
    "--disable-default-apps",
    "--disable-extensions",
    "--disable-sync",
    "--metrics-recording-only",
    "about:blank",
  ],
  { stdio: ["ignore", "ignore", "pipe"] },
);

let browserSocketUrl;
let stderr = "";
let spawnError;
chrome.on("error", (error) => {
  spawnError = error;
});
chrome.stderr.setEncoding("utf8");
chrome.stderr.on("data", (chunk) => {
  stderr += chunk;
  const match = chunk.match(/DevTools listening on (ws:\/\/[^\s]+)/);
  if (match) browserSocketUrl = match[1];
});

const delay = (milliseconds) =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));
const sanitizeDiagnostic = (value) =>
  String(value ?? "").replace(
    /([?&#](?:state|token)=)[^&#\s)]+/giu,
    "$1[redacted]",
  );
const telegramTaskId = (commandId) => {
  const raw = commandId.replaceAll("-", "").toLowerCase();
  const suffix = (BigInt(`0x${raw.slice(20)}`) ^ 1n)
    .toString(16)
    .padStart(12, "0");
  const variant = ((Number.parseInt(raw[16], 16) & 3) | 8).toString(16);
  return `${raw.slice(0, 8)}-${raw.slice(8, 12)}-5${
    raw.slice(13, 16)
  }-${variant}${raw.slice(17, 20)}-${suffix}`;
};

async function waitForBrowserSocket() {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    if (browserSocketUrl) return browserSocketUrl;
    if (spawnError) throw spawnError;
    if (chrome.exitCode !== null) {
      throw new Error(`Chrome exited before CDP was ready: ${stderr}`);
    }
    await delay(100);
  }
  throw new Error(`Timed out waiting for Chrome DevTools: ${stderr}`);
}

class CdpClient {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    this.listeners = [];
    socket.addEventListener("message", (event) => {
      const message = JSON.parse(event.data);
      if (message.id) {
        const pending = this.pending.get(message.id);
        if (!pending) return;
        this.pending.delete(message.id);
        if (message.error) pending.reject(new Error(message.error.message));
        else pending.resolve(message.result ?? {});
        return;
      }
      for (const listener of this.listeners) listener(message);
    });
  }

  send(method, params = {}, sessionId) {
    const id = this.nextId++;
    const message = { id, method, params };
    if (sessionId) message.sessionId = sessionId;
    this.socket.send(JSON.stringify(message));
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
    });
  }
}

let socket;
try {
  const wsUrl = await waitForBrowserSocket();
  socket = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => {
    socket.addEventListener("open", resolve, { once: true });
    socket.addEventListener("error", reject, { once: true });
  });
  const cdp = new CdpClient(socket);
  const { targetId } = await cdp.send("Target.createTarget", {
    url: "about:blank",
  });
  const attached = await cdp.send("Target.attachToTarget", {
    targetId,
    flatten: true,
  });
  let sessionId = attached.sessionId;

  const diagnostics = [];
  let sentryEnvelopeAttempted = false;
  let turnstileHandoffRequested = false;
  let turnstileHandoffEvents = 0;
  let turnstileChallengeStateLeakedToNetwork = false;
  let turnstileHandoffUrl;
  let turnstileScriptRequests = 0;
  let challengeWasmRequested = false;
  cdp.listeners.push((message) => {
    if (message.sessionId !== sessionId) return;
    if (message.method === "Log.entryAdded") {
      diagnostics.push(sanitizeDiagnostic(message.params.entry.text));
    } else if (message.method === "Runtime.exceptionThrown") {
      diagnostics.push(
        sanitizeDiagnostic(
          message.params.exceptionDetails.exception?.description ??
            message.params.exceptionDetails.text,
        ),
      );
    } else if (message.method === "Runtime.consoleAPICalled") {
      diagnostics.push(
        sanitizeDiagnostic(
          message.params.args
            .map((argument) => argument.value ?? argument.description ?? "")
            .join(" "),
        ),
      );
    } else if (message.method === "Network.loadingFailed") {
      const { blockedReason, errorText } = message.params;
      if (blockedReason === "csp") {
        diagnostics.push(`CSP blocked: ${errorText}`);
      }
    } else if (message.method === "Network.requestWillBeSent") {
      const requestUrl = message.params.request.url;
      if (
        requestUrl.startsWith(
          "https://challenges.cloudflare.com/turnstile/v0/api.js",
        )
      ) {
        turnstileScriptRequests += 1;
      }
      if (
        /\.wasm(?:[?#]|$)/i.test(requestUrl) &&
        new URL(message.params.documentURL).pathname === "/auth/challenge"
      ) {
        challengeWasmRequested = true;
      }
      if (requestUrl.startsWith("pomodoist://captcha-callback?")) {
        turnstileHandoffRequested = true;
        turnstileHandoffEvents += 1;
        turnstileHandoffUrl = requestUrl;
      }
      const parsedRequestUrl = new URL(requestUrl);
      if (
        parsedRequestUrl.pathname === "/auth/challenge" &&
        parsedRequestUrl.searchParams.has("state")
      ) {
        turnstileChallengeStateLeakedToNetwork = true;
      }
      if (
        /^https:\/\/o\d+\.ingest\.sentry\.io\/api\/\d+\/envelope\/$/.test(
          requestUrl,
        )
      ) {
        sentryEnvelopeAttempted = true;
      }
    } else if (message.method === "Page.frameRequestedNavigation") {
      if (message.params.url?.startsWith("pomodoist://captcha-callback?")) {
        turnstileHandoffRequested = true;
        turnstileHandoffEvents += 1;
        turnstileHandoffUrl = message.params.url;
      }
    }
  });

  await Promise.all([
    cdp.send("Page.enable", {}, sessionId),
    cdp.send("Runtime.enable", {}, sessionId),
    cdp.send("Log.enable", {}, sessionId),
    cdp.send("Network.enable", {}, sessionId),
  ]);
  await cdp.send("Page.navigate", { url: targetUrl }, sessionId);

  let loaderGone = false;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const evaluation = await cdp.send(
      "Runtime.evaluate",
      {
        expression:
          "document.getElementById('pomodoist-web-loader') === null && " +
          "document.querySelector('flutter-view') !== null",
        returnByValue: true,
      },
      sessionId,
    );
    if (evaluation.result?.value === true) {
      loaderGone = true;
      break;
    }
    await delay(250);
  }
  if (loaderGone) {
    await cdp.send(
      "Runtime.evaluate",
      {
        expression: `(() => {
          const dsn = new URL(window.pomodoistRuntimeConfig.sentryDsn);
          const project = dsn.pathname.slice(1);
          fetch(dsn.origin + '/api/' + project + '/envelope/', {
            method: 'POST', mode: 'no-cors', body: '{}'
          }).catch(() => {});
        })()`,
      },
      sessionId,
    );
    for (
      let attempt = 0;
      attempt < 40 && !sentryEnvelopeAttempted;
      attempt += 1
    ) {
      await delay(100);
    }
  }

  const origin = new URL(targetUrl).origin;
  const { targetId: challengeTargetId } = await cdp.send(
    "Target.createTarget",
    { url: "about:blank" },
  );
  const challengeTarget = await cdp.send("Target.attachToTarget", {
    targetId: challengeTargetId,
    flatten: true,
  });
  sessionId = challengeTarget.sessionId;
  await Promise.all([
    cdp.send("Page.enable", {}, sessionId),
    cdp.send("Runtime.enable", {}, sessionId),
    cdp.send("Log.enable", {}, sessionId),
    cdp.send("Network.enable", {}, sessionId),
  ]);
  const challengeState = "A".repeat(43);
  await cdp.send("Runtime.evaluate", {
    expression: "localStorage.clear(); sessionStorage.clear()",
  }, sessionId);
  const requestsBeforeInvalid = turnstileScriptRequests;
  const missingStateUrl = `${origin}/auth/challenge?returnTo=` +
    encodeURIComponent("pomodoist://captcha-callback");
  await cdp.send("Page.navigate", { url: missingStateUrl }, sessionId);
  let missingStateRejected = false;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const evaluation = await cdp.send("Runtime.evaluate", {
      expression: "location.pathname === '/auth/challenge' && " +
        "location.hash === '' && " +
        "document.body?.dataset.status === 'invalid'",
      returnByValue: true,
    }, sessionId);
    if (evaluation.result?.value === true) {
      missingStateRejected = true;
      break;
    }
    await delay(100);
  }
  await delay(200);
  const missingStateSkippedTurnstile =
    turnstileScriptRequests === requestsBeforeInvalid;

  const invalidStateUrl = `${missingStateUrl}#state=short`;
  const invalidTarget = await cdp.send("Target.createTarget", {
    url: "about:blank",
  });
  const invalidAttachment = await cdp.send("Target.attachToTarget", {
    targetId: invalidTarget.targetId,
    flatten: true,
  });
  sessionId = invalidAttachment.sessionId;
  await Promise.all([
    cdp.send("Page.enable", {}, sessionId),
    cdp.send("Runtime.enable", {}, sessionId),
    cdp.send("Log.enable", {}, sessionId),
    cdp.send("Network.enable", {}, sessionId),
  ]);
  await cdp.send("Page.navigate", { url: invalidStateUrl }, sessionId);
  let invalidStateRejected = false;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const evaluation = await cdp.send("Runtime.evaluate", {
      expression: "location.hash === '#state=short' && " +
        "document.body?.dataset.status === 'invalid'",
      returnByValue: true,
    }, sessionId);
    if (evaluation.result?.value === true) {
      invalidStateRejected = true;
      break;
    }
    await delay(100);
  }
  await delay(200);
  const invalidStateSkippedTurnstile =
    turnstileScriptRequests === requestsBeforeInvalid;

  const challengeUrl = `${origin}/auth/challenge?returnTo=` +
    encodeURIComponent("pomodoist://captcha-callback") +
    `#state=${challengeState}`;
  const validTarget = await cdp.send("Target.createTarget", {
    url: "about:blank",
  });
  const validAttachment = await cdp.send("Target.attachToTarget", {
    targetId: validTarget.targetId,
    flatten: true,
  });
  sessionId = validAttachment.sessionId;
  await Promise.all([
    cdp.send("Page.enable", {}, sessionId),
    cdp.send("Runtime.enable", {}, sessionId),
    cdp.send("Log.enable", {}, sessionId),
    cdp.send("Network.enable", {}, sessionId),
  ]);
  await cdp.send("Page.navigate", { url: challengeUrl }, sessionId);
  let turnstileReady = false;
  for (let attempt = 0; attempt < 120; attempt += 1) {
    const evaluation = await cdp.send(
      "Runtime.evaluate",
      {
        expression: "typeof window.turnstile !== 'undefined' && " +
          "document.getElementById('pomodoist-turnstile-script') !== null && " +
          "document.getElementById('pomodoist-captcha-challenge') !== null",
        returnByValue: true,
      },
      sessionId,
    );
    if (evaluation.result?.value === true) turnstileReady = true;
    if (turnstileReady && turnstileHandoffRequested) break;
    await delay(250);
  }
  let turnstileCallbackValid = false;
  let turnstileCallbackShape;
  if (turnstileHandoffUrl) {
    const callback = new URL(turnstileHandoffUrl);
    const keys = [...callback.searchParams.keys()];
    const token = callback.searchParams.get("token") ?? "";
    turnstileCallbackShape = {
      protocol: callback.protocol,
      hostname: callback.hostname,
      pathname: callback.pathname,
      hasCredentials: callback.username !== "" || callback.password !== "",
      port: callback.port,
      hash: callback.hash,
      keys,
      stateCount: callback.searchParams.getAll("state").length,
      stateLength: callback.searchParams.get("state")?.length ?? 0,
      stateMatches: callback.searchParams.get("state") === challengeState,
      tokenCount: callback.searchParams.getAll("token").length,
      tokenLength: token.length,
      tokenHasControls: /[\u0000-\u001f\u007f-\u009f]/.test(token),
    };
    turnstileCallbackValid = callback.protocol === "pomodoist:" &&
      callback.hostname === "captcha-callback" &&
      callback.pathname === "" &&
      callback.username === "" &&
      callback.password === "" &&
      callback.port === "" &&
      callback.hash === "" &&
      keys.length === 2 &&
      keys[0] === "state" &&
      keys[1] === "token" &&
      callback.searchParams.getAll("state").length === 1 &&
      callback.searchParams.get("state") === challengeState &&
      callback.searchParams.getAll("token").length === 1 &&
      token.length > 0 &&
      token.length <= 2048 &&
      !/[\u0000-\u001f\u007f-\u009f]/.test(token);
  }

  await delay(500);
  const handoffEventsBeforeRetry = turnstileHandoffEvents;
  let turnstileManualRetryButtonFound = false;
  let turnstileManualRetryObserved = false;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const evaluation = await cdp.send(
      "Runtime.evaluate",
      {
        expression: `(() => {
          const retry = document.getElementById('return-to-app');
          if (!retry) return false;
          if (retry.hidden) return false;
          retry.click();
          return true;
        })()`,
        returnByValue: true,
      },
      sessionId,
    );
    if (evaluation.result?.value === true) {
      turnstileManualRetryButtonFound = true;
      break;
    }
    await delay(100);
  }
  const challengeRuntimeStatus = await cdp.send("Runtime.evaluate", {
    expression: `(() => ({
      hasFlutter: [...document.scripts].some((script) =>
        /main\\.dart\\.js|flutter_bootstrap\\.js/.test(script.src)) ||
        document.querySelector('flutter-view') !== null,
      storageEmpty: localStorage.length === 0 && sessionStorage.length === 0,
      hashStateLength: new URLSearchParams(location.hash.slice(1))
        .get('state')?.length ?? 0,
      status: document.body?.dataset.status,
    }))()`,
    returnByValue: true,
  }, sessionId);
  for (let attempt = 0; attempt < 20; attempt += 1) {
    if (turnstileHandoffEvents > handoffEventsBeforeRetry) {
      turnstileManualRetryObserved = true;
      break;
    }
    await delay(100);
  }

  await cdp.send("Page.navigate", { url: `${origin}/telegram/` }, sessionId);
  let telegramOutsideReady = false;
  let telegramHasFlutterBundle = true;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    const evaluation = await cdp.send(
      "Runtime.evaluate",
      {
        expression: `(() => ({
          outsideReady: document.getElementById('outside')?.hidden === false &&
            document.getElementById('open-bot')?.href.includes('pomodoist_test_bot'),
          hasFlutterBundle: [...document.scripts].some((script) =>
            /main\\.dart\\.js|flutter_bootstrap\\.js/.test(script.src))
        }))()`,
        returnByValue: true,
      },
      sessionId,
    );
    telegramOutsideReady = evaluation.result?.value?.outsideReady === true;
    telegramHasFlutterBundle =
      evaluation.result?.value?.hasFlutterBundle === true;
    if (telegramOutsideReady) break;
    await delay(100);
  }

  await cdp.send("Runtime.evaluate", {
    expression: "localStorage.clear(); sessionStorage.clear()",
  }, sessionId);
  await cdp.send("Page.addScriptToEvaluateOnNewDocument", {
    source: `(() => {
      const originalFetch = window.fetch.bind(window);
      window.__telegramCommands = [];
      window.__telegramResponses = [];
      window.fetch = (input, init = {}) => {
        if (!String(input).endsWith('/functions/v1/pomodoist-telegram')) {
          return originalFetch(input, init);
        }
        const body = JSON.parse(init.body ?? '{}');
        if (body.action === 'snapshot') {
          return Promise.resolve(new Response(JSON.stringify({
            ok: true,
            data: { account: { linked: false }, inbox: [], focus: null },
          }), { status: 200, headers: { 'content-type': 'application/json' } }));
        }
        window.__telegramCommands.push(body.command);
        return new Promise((resolve) => window.__telegramResponses.push(resolve));
      };
    })()`,
  }, sessionId);
  const initData = new URLSearchParams({
    auth_date: "1785844800",
    user: JSON.stringify({ id: 42, language_code: "en" }),
    hash: "browser-test",
  }).toString();
  const telegramInsideUrl =
    `${origin}/telegram/?browser-test=1#${new URLSearchParams({
      tgWebAppData: initData,
      tgWebAppVersion: "9.0",
      tgWebAppPlatform: "web",
    })}`;
  await cdp.send("Page.navigate", { url: telegramInsideUrl }, sessionId);
  let telegramInsideReady = false;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const evaluation = await cdp.send("Runtime.evaluate", {
      expression: "document.getElementById('app')?.hidden === false && " +
        "document.getElementById('task-input') !== null",
      returnByValue: true,
    }, sessionId);
    if (evaluation.result?.value === true) {
      telegramInsideReady = true;
      break;
    }
    await delay(100);
  }
  const telegramInsideStatus = await cdp.send("Runtime.evaluate", {
    expression: `(() => ({
      href: location.href,
      mockInstalled: Array.isArray(window.__telegramCommands),
      initDataLength: window.Telegram?.WebApp?.initData?.length ?? 0,
      loadingHidden: document.getElementById('loading')?.hidden,
      appHidden: document.getElementById('app')?.hidden,
      errorHidden: document.getElementById('error')?.hidden,
      errorText: document.getElementById('error-text')?.textContent,
    }))()`,
    returnByValue: true,
  }, sessionId);
  const telegramImmediate = await cdp.send("Runtime.evaluate", {
    expression: `(() => {
      const input = document.getElementById('task-input');
      input.value = 'Immediate task';
      document.getElementById('add-form').requestSubmit();
      const task = [...document.querySelectorAll('.task')].find((item) =>
        item.querySelector('.task-title')?.textContent === 'Immediate task');
      const focus = task?.querySelector('[data-focus]');
      const added = input.value === '' && task != null;
      const focusEnabled = focus?.disabled === false;
      focus?.click();
      return {
        added,
        focusEnabled,
        focusStarted: document.getElementById('focus-card')?.hidden === false,
      };
    })()`,
    returnByValue: true,
  }, sessionId);
  let createRequest;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const evaluation = await cdp.send("Runtime.evaluate", {
      expression: "window.__telegramCommands?.[0]",
      returnByValue: true,
    }, sessionId);
    createRequest = evaluation.result?.value;
    if (createRequest != null) break;
    await delay(100);
  }
  const createdTaskId = createRequest == null
    ? null
    : telegramTaskId(createRequest.id);
  if (createRequest != null) {
    const payload = JSON.stringify({
      ok: true,
      data: {
        account: { linked: false },
        inbox: [{ id: createdTaskId, content: "Immediate task" }],
        focus: null,
      },
    });
    await cdp.send("Runtime.evaluate", {
      expression: `window.__telegramResponses[0](new Response(${
        JSON.stringify(payload)
      }, {
        status: 200, headers: { 'content-type': 'application/json' }
      }))`,
    }, sessionId);
  }
  let focusRequest;
  for (let attempt = 0; attempt < 80; attempt += 1) {
    const evaluation = await cdp.send("Runtime.evaluate", {
      expression: "window.__telegramCommands?.[1]",
      returnByValue: true,
    }, sessionId);
    focusRequest = evaluation.result?.value;
    if (focusRequest != null) break;
    await delay(100);
  }
  const telegramQueuedFocusUsesServerTask =
    focusRequest?.type === "focus.start" &&
    focusRequest?.taskId === createdTaskId;

  const cspViolations = diagnostics.filter((message) =>
    /content security policy|refused to|csp blocked/i.test(message)
  );
  if (
    !loaderGone ||
    cspViolations.length > 0 ||
    !sentryEnvelopeAttempted ||
    !missingStateRejected ||
    !missingStateSkippedTurnstile ||
    !invalidStateRejected ||
    !invalidStateSkippedTurnstile ||
    !turnstileReady ||
    !turnstileHandoffRequested ||
    !turnstileCallbackValid ||
    !turnstileManualRetryButtonFound ||
    !turnstileManualRetryObserved ||
    turnstileChallengeStateLeakedToNetwork ||
    challengeWasmRequested ||
    challengeRuntimeStatus.result?.value?.hasFlutter !== false ||
    challengeRuntimeStatus.result?.value?.storageEmpty !== true ||
    !telegramOutsideReady ||
    telegramHasFlutterBundle ||
    !telegramInsideReady ||
    telegramImmediate.result?.value?.added !== true ||
    telegramImmediate.result?.value?.focusEnabled !== true ||
    telegramImmediate.result?.value?.focusStarted !== true ||
    !telegramQueuedFocusUsesServerTask
  ) {
    throw new Error(
      JSON.stringify(
        {
          loaderGone,
          sentryEnvelopeAttempted,
          missingStateRejected,
          missingStateSkippedTurnstile,
          invalidStateRejected,
          invalidStateSkippedTurnstile,
          turnstileReady,
          turnstileHandoffRequested,
          turnstileCallbackValid,
          turnstileManualRetryButtonFound,
          turnstileManualRetryObserved,
          turnstileChallengeStateLeakedToNetwork,
          challengeWasmRequested,
          challengeRuntimeStatus: challengeRuntimeStatus.result?.value,
          telegramOutsideReady,
          telegramHasFlutterBundle,
          telegramInsideReady,
          telegramInsideStatus: telegramInsideStatus.result?.value,
          telegramImmediate: telegramImmediate.result?.value,
          telegramQueuedFocusUsesServerTask,
          telegramCommands: [createRequest, focusRequest].filter(Boolean),
          turnstileCallbackShape,
          cspViolations,
          diagnostics: diagnostics.filter(Boolean).slice(-20),
        },
        null,
        2,
      ),
    );
  }

  console.log(
    "Headless browser smoke passed: Flutter, static Turnstile challenge, and Telegram rendered without CSP violations.",
  );
} catch (error) {
  console.error(`Headless browser smoke failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (socket) socket.close();
  if (chrome.exitCode === null) {
    const exited = new Promise((resolve) => chrome.once("exit", resolve));
    chrome.kill("SIGTERM");
    await Promise.race([exited, delay(1000)]);
    if (chrome.exitCode === null) {
      chrome.kill("SIGKILL");
      await Promise.race([exited, delay(1000)]);
    }
  }
  await rm(profile, { recursive: true, force: true });
}
