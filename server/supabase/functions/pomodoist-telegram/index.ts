import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { handlePomodoistTelegram } from "./pomodoist_telegram.ts";
import { createTelegramStore } from "./store.ts";
import * as telegramRuntime from "../pomodoist-watch/pomodoist_watch.ts";
import { createTelegramApi, handleTelegramWebhook, isTelegramWebhookRequest } from "./bot.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const botToken = Deno.env.get("POMODOIST_TELEGRAM_BOT_TOKEN") ?? "";
const webAppUrl = Deno.env.get("POMODOIST_WEB_URL") ??
  (supabaseUrl.includes("ewauihswbwduvklrozke")
    ? "https://app.pomodoist.com"
    : "https://app-test.pomodoist.com");
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
  global: { fetch: (input, init) => fetch(input, { ...init, signal: (init && "signal" in init ? init.signal : undefined) ?? AbortSignal.timeout(10000) }) },
});
const store = createTelegramStore(admin, webAppUrl, telegramRuntime);
const call = createTelegramApi(botToken, fetch, Deno.env.get("POMODOIST_TELEGRAM_API_BASE_URL") ?? "https://api.telegram.org");
Deno.serve(request => isTelegramWebhookRequest(request)
  ? handleTelegramWebhook(request, {
    secret: Deno.env.get("POMODOIST_TELEGRAM_WEBHOOK_SECRET") ?? "",
    timeZone: Deno.env.get("POMODOIST_TELEGRAM_TIME_ZONE") ?? "UTC",
    botToken, webAppUrl, store, call,
  })
  : handlePomodoistTelegram(request, { botToken, allowedOrigin: webAppUrl, store }));
