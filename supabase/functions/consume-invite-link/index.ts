import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verify } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

type ConsumeInviteRequest = {
  sig: string;
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

    if (!supabaseUrl || !anonKey || !serviceRoleKey || !inviteJwtSecret) {
      return jsonResponse({ error: "Missing required environment variables" }, 500);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const apikey = req.headers.get("apikey") ?? "";
    if (authHeader.startsWith("Bearer ") === false || apikey !== anonKey) {
      return jsonResponse({ error: "Unauthorized client" }, 401);
    }

    const payload = (await req.json()) as ConsumeInviteRequest;
    if (!payload?.sig) {
      return jsonResponse({ error: "sig is required" }, 400);
    }

    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(inviteJwtSecret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );

    const decoded = (await verify(payload.sig, key)) as Record<string, unknown>;
    const nonce = String(decoded.nonce ?? "");
    const inviteToken = String(decoded.token ?? "");
    const channel = String(decoded.channel ?? "");
    const tokenType = String(decoded.typ ?? "");

    if (!nonce || !inviteToken || !channel || tokenType !== "invite_link") {
      return jsonResponse({ error: "invalid invite payload" }, 400);
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey);
    const { data: row, error: selectError } = await adminClient
      .from("invite_link_nonces")
      .select("nonce, expires_at, used_at, invite_token, channel")
      .eq("nonce", nonce)
      .maybeSingle();

    if (selectError || !row) {
      return jsonResponse({ error: "nonce not found" }, 404);
    }

    if (row.invite_token !== inviteToken || row.channel !== channel) {
      return jsonResponse({ error: "payload mismatch" }, 400);
    }
    if (row.used_at) {
      return jsonResponse({ error: "invite already consumed" }, 409);
    }
    if (new Date(row.expires_at).getTime() <= Date.now()) {
      return jsonResponse({ error: "invite expired" }, 410);
    }

    const { error: updateError } = await adminClient
      .from("invite_link_nonces")
      .update({ used_at: new Date().toISOString() })
      .eq("nonce", nonce)
      .is("used_at", null);

    if (updateError) {
      return jsonResponse({ error: `nonce update failed: ${updateError.message}` }, 500);
    }

    return jsonResponse({
      valid: true,
      inviteToken,
      channel,
      nonce,
    });
  } catch (error) {
    return jsonResponse({ error: `unexpected error: ${String(error)}` }, 500);
  }
});
