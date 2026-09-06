import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "npm:@supabase/supabase-js@2";

import {
  verifyAppleAppStoreNotificationJws,
  verifyAppleStoreTransactionJws,
} from "../_shared/apple_app_transaction.ts";
import { handlePomodoistAppStoreNotification } from "./pomodoist_app_store_notifications.ts";

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return handlePomodoistAppStoreNotification(req, {
    verifyNotification: verifyAppleAppStoreNotificationJws,
    verifyTransaction: verifyAppleStoreTransactionJws,
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
