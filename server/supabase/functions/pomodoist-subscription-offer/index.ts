import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAppleStoreTransactionJws } from "../_shared/apple_app_transaction.ts";
import { fetchAppleHistory, promotionalSignature } from "./apple_server.ts";
import { handleSubscriptionOffer } from "./pomodoist_subscription_offer.ts";

Deno.serve((req) => {
  const url = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const credentials = {
    keyID: Deno.env.get("APPLE_IAP_KEY_ID") ?? "",
    issuerId: Deno.env.get("APPLE_IAP_ISSUER_ID") ?? "",
    privateKey: (Deno.env.get("APPLE_IAP_PRIVATE_KEY") ?? "").replace(
      /\\n/g,
      "\n",
    ),
  };
  // Apple signatures do not encode an environment. Sandbox mode must only run
  // on a private test signer; never expose it alongside the production signer.
  const environment = Deno.env.get("APPLE_RETURN_OFFERS_ENVIRONMENT") ??
    "Production";
  return handleSubscriptionOffer(req, {
    environment: environment === "Sandbox" ? "Sandbox" : "Production",
    enabled: Deno.env.get("APPLE_RETURN_OFFERS_ENABLED") === "true",
    // No inferred V2 expiry: activation requires an Apple-confirmed upper bound.
    signatureMaxAgeSeconds: Number(
      Deno.env.get("APPLE_RETURN_OFFER_SIGNATURE_MAX_AGE_SECONDS"),
    ),
    configured:
      [...Object.values(credentials), url, anonKey, serviceRoleKey].every(
        Boolean,
      ) &&
      ["Production", "Sandbox"].includes(environment),
    authenticate: async (authorization) => {
      if (!authorization || authorization === `Bearer ${anonKey}`) return null;
      const auth = createClient(url, anonKey, {
        global: { headers: { Authorization: authorization } },
      });
      const { data: { user }, error } = await auth.auth.getUser();
      if (error || !user) throw new Error("invalid_authentication");
      const { data: accountToken, error: tokenError } = await auth.rpc(
        "get_apple_app_account_token",
      );
      if (tokenError || typeof accountToken !== "string") {
        throw new Error("invalid_account_token");
      }
      return { userId: user.id, accountToken };
    },
    verify: verifyAppleStoreTransactionJws,
    history: (seed) => fetchAppleHistory(seed, credentials),
    sign: (productId, transactionId, now) =>
      promotionalSignature(credentials, productId, transactionId, now),
    state: async (params) => {
      const admin = createClient(
        url,
        serviceRoleKey,
      );
      const { data, error } = await admin.rpc(
        "pomodoist_subscription_offer_state",
        params,
      );
      if (error || data == null || typeof data.code !== "string") {
        throw new Error("offer_state_unavailable");
      }
      return data;
    },
  });
});
