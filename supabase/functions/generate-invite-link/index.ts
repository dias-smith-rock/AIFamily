import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

type GenerateInviteRequest = {
  token: string;
  channel: "wechat" | "app" | "whatsapp" | "sms";
  expiresInSeconds?: number;
};

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

function normalizeTTL(raw?: number): number {
  const fallback = 900;
  if (typeof raw !== "number" || Number.isNaN(raw)) return fallback;
  return Math.max(60, Math.min(3600, Math.floor(raw)));
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
    const inviteJwtSecret = Deno.env.get("INVITE_JWT_SECRET") ?? "";
    const inviteBaseUrl = Deno.env.get("INVITE_BASE_URL") ?? "https://aifamily.app/invite";

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !inviteJwtSecret) {
      return jsonResponse({ error: "Missing required environment variables" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const apikey = req.headers.get("apikey") ?? "";
    if (authHeader.startsWith("Bearer ") === false || apikey !== anonKey) {
      return jsonResponse({ error: "Unauthorized client" }, 401);
    }

    const payload = (await req.json()) as GenerateInviteRequest;
    if (!payload?.token || !payload?.channel) {
      return jsonResponse({ error: "token and channel are required" }, 400);
    }

    const ttl = normalizeTTL(payload.expiresInSeconds);
    const nonce = crypto.randomUUID();
    const now = Math.floor(Date.now() / 1000);
    const exp = now + ttl;

    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(inviteJwtSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"],
    );

    const signedToken = await create(
      { alg: "HS256", typ: "JWT" },
      {
        typ: "invite_link",
        token: payload.token,
        channel: payload.channel,
        nonce,
        iat: getNumericDate(0),
        exp: getNumericDate(ttl),
      },
      key,
    );

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { error: insertError } = await adminClient
      .from("invite_link_nonces")
      .insert({
        nonce,
        invite_token: payload.token,
        channel: payload.channel,
        expires_at: new Date(exp * 1000).toISOString(),
        used_at: null,
      });

    if (insertError) {
      return jsonResponse({ error: `nonce write failed: ${insertError.message}` }, 500);
    }

    const url = new URL(inviteBaseUrl);
    url.searchParams.set("sig", signedToken);
    url.searchParams.set("ch", payload.channel);

    return jsonResponse({
      url: url.toString(),
      expiresAt: new Date(exp * 1000).toISOString(),
      nonce,
    });
  } catch (error) {
    return jsonResponse({ error: `unexpected error: ${String(error)}` }, 500);
  }
});
