import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  Environment,
  SignedDataVerifier,
} from "@apple/app-store-server-library";

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
  environment?: "sandbox" | "production";
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

async function loadAppleRootCAs(): Promise<Buffer[]> {
  const urls = [
    "https://www.apple.com/appleca/AppleIncRootCertificate.cer",
    "https://www.apple.com/certificateauthority/AppleRootCA-G3.cer",
  ];
  const buffers: Buffer[] = [];
  for (const url of urls) {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch Apple root CA: ${url}`);
    }
    const bytes = new Uint8Array(await response.arrayBuffer());
    buffers.push(Buffer.from(bytes));
  }
  return buffers;
}

function toEnvironment(value?: string): Environment {
  return value === "sandbox" ? Environment.SANDBOX : Environment.PRODUCTION;
}

function millisToIso(value?: number | null): string | null {
  if (value == null || Number.isNaN(value)) return null;
  return new Date(value).toISOString();
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
    const appAppleIdRaw = Deno.env.get("APP_APPLE_ID") ?? "6775353963";

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

    const environment = toEnvironment(body.environment);
    const appAppleId = appAppleIdRaw ? Number(appAppleIdRaw) : undefined;
    const rootCAs = await loadAppleRootCAs();
    const verifier = new SignedDataVerifier(
      rootCAs,
      true,
      environment,
      BUNDLE_ID,
      appAppleId,
    );

    const decoded = await verifier.verifyAndDecodeTransaction(body.signedTransactionInfo);
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

    if (decoded.bundleId && decoded.bundleId !== BUNDLE_ID) {
      return jsonResponse({ error: "Bundle id mismatch" }, 400);
    }

    const paidAt = millisToIso(decoded.purchaseDate) ?? new Date().toISOString();
    const amount = decoded.price ?? 0;
    const currency = decoded.currency ?? "USD";
    const environmentLabel = environment === Environment.SANDBOX ? "sandbox" : "production";

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
      return jsonResponse({ error: rpcError.message }, 500);
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
    return jsonResponse({ error: message }, 500);
  }
});
