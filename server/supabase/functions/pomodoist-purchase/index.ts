import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import { verifyAppleStoreTransactionJws } from "../_shared/apple_app_transaction.ts";
import { handlePomodoistPurchase } from "./pomodoist_purchase.ts";

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  return handlePomodoistPurchase(req, {
    authenticate: async (authorization) => {
      const auth = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
      });
      const {
        data: { user },
        error: userError,
      } = await auth.auth.getUser();
      if (userError || !user) return null;
      const { data: accountToken, error: tokenError } = await auth.rpc(
        "get_apple_app_account_token",
      );
      if (tokenError || typeof accountToken !== "string") {
        throw new Error("Could not read App Account Token.");
      }
      return { userId: user.id, accountToken };
    },
    verifyStoreTransaction: verifyAppleStoreTransactionJws,
    recordPurchase: async (params) => {
      const admin = createClient(url, serviceRoleKey);
      const { data, error } = await admin.rpc(
        "record_pomodoist_purchase",
        params,
      );
      return {
        data,
        error: error == null ? null : { message: error.message },
      };
    },
  });
});
