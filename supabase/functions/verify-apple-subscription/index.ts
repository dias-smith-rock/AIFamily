import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  normalizeAppleEnvironment,
  verifyAppleTransactionJws,
} from "./apple_jws_verify.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const BUNDLE_ID = "com.aifamilygroup.reminder";
const PRODUCT_PLAN: Record<string, string> = {
  "wesync.vip.monthly": "pro_monthly",
  "wesync.vip.yearly": "pro_yearly",
};

type VerifyAppleSubscriptionRequest = {
  signedTransactionInfo: string;
  environment?: "sandbox" | "production" | "xcode";
};

type ActivatePremiumRpcResult = {
  order_id: string;
  user_id: string;
  plan_purchased: string;
  expires_at: string | null;
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

async function loadAppleRootCAs(): Promise<Uint8Array[]> {
  const urls = [
    "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
    "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  ];
  const certificates: Uint8Array[] = [];
  for (const url of urls) {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch Apple root CA: ${url}`);
    }
    certificates.push(new Uint8Array(await response.arrayBuffer()));
  }
  return certificates;
}

function millisToIso(value?: number | null): string | null {
  if (value == null || Number.isNaN(value)) return null;
  return new Date(value).toISOString();
}

function environmentLabelFromPayload(value?: string): string {
  return normalizeAppleEnvironment(value);
}

function environmentMatchesRequest(
  payloadEnvironment: string | undefined,
  requested?: VerifyAppleSubscriptionRequest["environment"],
): boolean {
  if (!requested) return true;

  const payload = normalizeAppleEnvironment(payloadEnvironment);
  const request = normalizeAppleEnvironment(requested);

  if (payload === request) return true;

  // Xcode StoreKit 本地测试：客户端可能上报 sandbox，JWS payload 为 Xcode。
  if (payload === "xcode" && (request === "xcode" || request === "sandbox")) {
    return true;
  }

  return false;
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

    if (!supabaseUrl || !anonKey || !serviceRoleKey) {
      return jsonResponse({ error: "Missing Supabase environment variables" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }

    const body = (await req.json()) as VerifyAppleSubscriptionRequest;
    if (!body.signedTransactionInfo?.trim()) {
      return jsonResponse({ error: "signedTransactionInfo is required" }, 400);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return jsonResponse({ error: "Unauthorized" }, 401);
    }
    const userId = userData.user.id;

    const rootCAs = await loadAppleRootCAs();
    const decoded = await verifyAppleTransactionJws(body.signedTransactionInfo, rootCAs);

    if (decoded.bundleId && decoded.bundleId !== BUNDLE_ID) {
      return jsonResponse({ error: "Bundle id mismatch" }, 400);
    }

    if (!environmentMatchesRequest(decoded.environment, body.environment)) {
      return jsonResponse({
        error: `Environment mismatch: payload=${decoded.environment ?? "unknown"}, request=${body.environment ?? "unknown"}`,
      }, 400);
    }

    const productId = decoded.productId ?? "";
    const planPurchased = PRODUCT_PLAN[productId];
    if (!planPurchased) {
      return jsonResponse({ error: `Unsupported productId: ${productId}` }, 400);
    }

    const expiresAt = millisToIso(decoded.expiresDate);
    if (expiresAt && new Date(expiresAt).getTime() <= Date.now()) {
      return jsonResponse({ error: "Subscription has expired" }, 400);
    }

    const transactionId = decoded.transactionId ?? decoded.originalTransactionId;
    if (!transactionId) {
      return jsonResponse({ error: "Missing transaction id in signed payload" }, 400);
    }

    const paidAt = millisToIso(decoded.purchaseDate) ?? new Date().toISOString();
    const amount = Number(decoded.price ?? 0);
    const currency = decoded.currency ?? "USD";
    const environmentLabel = environmentLabelFromPayload(decoded.environment);

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: rpcData, error: rpcError } = await adminClient.rpc(
      "activate_premium_from_apple",
      {
        p_user_id: userId,
        p_plan_purchased: planPurchased,
        p_amount: amount,
        p_currency: currency,
        p_environment: environmentLabel,
        p_external_transaction_id: transactionId,
        p_expires_at: expiresAt,
        p_paid_at: paidAt,
      },
    );

    if (rpcError) {
      console.error("activate_premium_from_apple", rpcError);
      return jsonResponse({ error: rpcError.message, step: "activate_premium" }, 500);
    }

    const activation = rpcData as ActivatePremiumRpcResult;

    return jsonResponse({
      success: true,
      plan: planPurchased,
      productId,
      transactionId,
      expiresAt: activation?.expires_at ?? expiresAt,
    });
  } catch (error) {
    console.error("verify-apple-subscription", error);
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message, step: "apple_verify" }, 500);
  }
});
