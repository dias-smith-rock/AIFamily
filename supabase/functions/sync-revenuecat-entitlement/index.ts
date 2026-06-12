import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  type LocalEntitlementHint,
  isAnonymousRevenueCatUser,
  resolveSubscriberForAuthUser,
  validateLocalEntitlementHint,
  planFromProductId,
} from "../_shared/revenuecat.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type SyncRequestBody = {
  aliasAppUserIds?: string[];
  localEntitlement?: LocalEntitlementHint;
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

function parseRequestBody(raw: unknown): SyncRequestBody {
  if (!raw || typeof raw !== "object") return {};
  const body = raw as SyncRequestBody;
  return {
    aliasAppUserIds: Array.isArray(body.aliasAppUserIds) ? body.aliasAppUserIds : undefined,
    localEntitlement: body.localEntitlement,
  };
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

    const requestBody = parseRequestBody(await req.json().catch(() => ({})));
    const userId = userData.user.id.trim().toLowerCase();

    let { isPro, proExpiresAt, planPurchased, diagnostics, resolvedFromAppUserId } =
      await resolveSubscriberForAuthUser(
        userId,
        revenueCatSecret,
        requestBody.aliasAppUserIds ?? [],
      );

    let syncSource = "client_sync";

    if (
      !isPro &&
      validateLocalEntitlementHint(requestBody.localEntitlement) &&
      (
        isAnonymousRevenueCatUser(diagnostics.originalAppUserId) ||
        (requestBody.aliasAppUserIds?.some((id) => isAnonymousRevenueCatUser(id)) ?? false)
      )
    ) {
      isPro = true;
      proExpiresAt = requestBody.localEntitlement?.proExpiresAt ?? null;
      planPurchased = planFromProductId(requestBody.localEntitlement?.productId);
      syncSource = "client_local_hint";
      console.info("sync-revenuecat-entitlement: applying validated local entitlement hint", {
        userId,
        productId: requestBody.localEntitlement?.productId,
        originalAppUserId: diagnostics.originalAppUserId,
      });
    }

    if (!isPro) {
      console.warn("sync-revenuecat-entitlement: RC reports inactive", {
        userId,
        resolvedFromAppUserId,
        ...diagnostics,
      });
    } else if (resolvedFromAppUserId !== userId) {
      console.info("sync-revenuecat-entitlement: entitlement from alias", {
        userId,
        resolvedFromAppUserId,
        syncSource,
      });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: rpcData, error: rpcError } = await adminClient.rpc(
      "sync_user_entitlement_from_revenuecat",
      {
        p_user_id: userId,
        p_is_pro: isPro,
        p_pro_expires_at: isPro ? proExpiresAt : new Date().toISOString(),
        p_plan_purchased: planPurchased,
        p_source: syncSource,
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
      diagnostics,
      resolvedFromAppUserId,
      syncSource,
    });
  } catch (error) {
    console.error("sync-revenuecat-entitlement", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
