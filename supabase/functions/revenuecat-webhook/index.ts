import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  REVENUECAT_ACTIVATE_EVENTS,
  REVENUECAT_DEACTIVATE_EVENTS,
  isAnonymousRevenueCatUser,
  isSupabaseUserId,
  millisToIso,
  planFromProductId,
} from "../_shared/revenuecat.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type RevenueCatWebhookEvent = {
  type?: string;
  app_user_id?: string;
  product_id?: string;
  expiration_at_ms?: number | null;
  entitlement_ids?: string[] | null;
};

type RevenueCatWebhookBody = {
  api_version?: string;
  event?: RevenueCatWebhookEvent;
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

function normalizeAuthHeader(value: string | null): string {
  return (value ?? "").trim();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const expectedAuth = Deno.env.get("REVENUECAT_WEBHOOK_AUTHORIZATION") ?? "";
    const receivedAuth = normalizeAuthHeader(req.headers.get("Authorization"));
    if (!expectedAuth || receivedAuth !== expectedAuth) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!supabaseUrl || !serviceRoleKey) {
      return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
    }

    const body = (await req.json()) as RevenueCatWebhookBody;
    const event = body.event;
    const eventType = event?.type ?? "";
    const appUserId = event?.app_user_id?.trim() ?? "";

    if (!eventType) {
      return jsonResponse({ error: "Missing event type" }, 400);
    }

    if (isAnonymousRevenueCatUser(appUserId) || !isSupabaseUserId(appUserId)) {
      return jsonResponse({ handled: false, reason: "anonymous_or_non_uuid_app_user_id", eventType });
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const expiresAt = millisToIso(event?.expiration_at_ms);
    const planPurchased = planFromProductId(event?.product_id);

    let isPro: boolean | null = null;
    if (REVENUECAT_ACTIVATE_EVENTS.has(eventType)) {
      isPro = true;
    } else if (REVENUECAT_DEACTIVATE_EVENTS.has(eventType)) {
      isPro = false;
    } else if (eventType === "CANCELLATION") {
      const stillActive = event?.expiration_at_ms != null && event.expiration_at_ms > Date.now();
      isPro = stillActive;
    } else {
      return jsonResponse({ handled: false, eventType });
    }

    if (isPro && expiresAt && new Date(expiresAt).getTime() <= Date.now()) {
      isPro = false;
    }

    if (isPro === null) {
      return jsonResponse({ handled: false, eventType });
    }

    const { error } = await adminClient.rpc("sync_user_entitlement_from_revenuecat", {
      p_user_id: appUserId,
      p_is_pro: isPro,
      p_pro_expires_at: isPro ? expiresAt : new Date().toISOString(),
      p_plan_purchased: planPurchased,
      p_source: `webhook:${eventType.toLowerCase()}`,
    });

    if (error) {
      console.error("sync_user_entitlement_from_revenuecat", error);
      return jsonResponse({ error: error.message, step: "sync_rpc" }, 500);
    }

    return jsonResponse({
      handled: true,
      eventType,
      isPro,
      appUserId,
    });
  } catch (error) {
    console.error("revenuecat-webhook", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
