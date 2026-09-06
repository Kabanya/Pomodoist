import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import { handlePomodoistTelegram } from "./pomodoist_telegram.ts";
import { createTelegramStore } from "./store.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const botToken = Deno.env.get("POMODOIST_TELEGRAM_BOT_TOKEN") ?? "";
const webAppUrl = Deno.env.get("POMODOIST_WEB_URL") ??
  (supabaseUrl.includes("ewauihswbwduvklrozke")
    ? "https://app.pomodoist.com"
    : "https://app-test.pomodoist.com");
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve((request) =>
  handlePomodoistTelegram(request, {
    botToken,
    allowedOrigin: webAppUrl,
    store: createTelegramStore(admin, webAppUrl),
  })
);
