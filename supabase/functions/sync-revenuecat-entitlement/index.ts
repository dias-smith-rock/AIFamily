import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  fetchRevenueCatSubscriber,
  resolveEntitlementState,
} from "../_shared/revenuecat.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const revenueCatSecret = Deno.env.get("REVENUECAT_SECRET_API_KEY") ?? "";

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
    }
    if (!revenueCatSecret) {
      return jsonResponse({ error: "Missing REVENUECAT_SECRET_API_KEY" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const userId = userData.user.id;
    const subscriber = await fetchRevenueCatSubscriber(userId, revenueCatSecret);
    const { isPro, proExpiresAt, planPurchased } = resolveEntitlementState(subscriber.subscriber);

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: rpcData, error: rpcError } = await adminClient.rpc(
      "sync_user_entitlement_from_revenuecat",
      {
        p_user_id: userId,
        p_is_pro: isPro,
        p_pro_expires_at: isPro ? proExpiresAt : new Date().toISOString(),
        p_plan_purchased: planPurchased,
        p_source: "client_sync",
      },
    );

    if (rpcError) {
      console.error("sync_user_entitlement_from_revenuecat", rpcError);
      return jsonResponse({ error: rpcError.message, step: "sync_rpc" }, 500);
    }

    const row = Array.isArray(rpcData) ? rpcData[0] : rpcData;

    return jsonResponse({
      synced: true,
      isPro,
      proExpiresAt: row?.pro_expires_at ?? proExpiresAt,
      planPurchased,
    });
  } catch (error) {
    console.error("sync-revenuecat-entitlement", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
