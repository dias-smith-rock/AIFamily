/**
 * Phase 2: Verify Apple App Store subscription JWS and return plan metadata.
 * MVP uses client-side StoreKit 2 verification; this endpoint is reserved for production hardening.
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type VerifyAppleSubscriptionRequest = {
  signedTransactionInfo?: string;
  transactionId?: string;
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
    const body = (await req.json()) as VerifyAppleSubscriptionRequest;
    if (!body.signedTransactionInfo && !body.transactionId) {
      return jsonResponse({ error: "signedTransactionInfo or transactionId is required" }, 400);
    }

    // TODO(Phase 2): Validate JWS with Apple App Store Server API / root certificates.
    return jsonResponse(
      {
        error: "not_implemented",
        message: "Server-side Apple subscription verification is not enabled yet.",
      },
      501,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unknown error";
    return jsonResponse({ error: message }, 500);
  }
});
