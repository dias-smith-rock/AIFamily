export const REVENUECAT_ENTITLEMENT_ID = "premium";

export const PRODUCT_PLAN_MAP: Record<string, string> = {
  "wesync.vip.monthly": "pro_monthly",
  "wesync.vip.yearly": "pro_yearly",
};

export const KNOWN_PRODUCT_IDS = Object.keys(PRODUCT_PLAN_MAP);

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isSupabaseUserId(value: string | undefined | null): boolean {
  if (!value) return false;
  return UUID_RE.test(value.trim());
}

export function isAnonymousRevenueCatUser(appUserId: string | undefined | null): boolean {
  if (!appUserId) return true;
  return appUserId.startsWith("$RCAnonymousID");
}

export function planFromProductId(productId?: string | null): string | null {
  if (!productId) return null;
  return PRODUCT_PLAN_MAP[productId] ?? null;
}

export function millisToIso(value?: number | null): string | null {
  if (value == null || Number.isNaN(value)) return null;
  return new Date(value).toISOString();
}

export function parseIsoDate(value?: string | null): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export type RevenueCatEntitlement = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  product_identifier?: string | null;
};

export type RevenueCatSubscription = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  product_identifier?: string | null;
  refunded_at?: string | null;
  billing_issues_detected_at?: string | null;
  unsubscribe_detected_at?: string | null;
};

export type RevenueCatSubscriberResponse = {
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement>;
    subscriptions?: Record<string, RevenueCatSubscription>;
    original_app_user_id?: string | null;
    aliases?: string[] | null;
  };
};

export type RevenueCatResolveDiagnostics = {
  entitlementKeys: string[];
  subscriptionKeys: string[];
  originalAppUserId: string | null;
  resolvedFrom: "premium_entitlement" | "entitlement_product" | "subscription" | "none";
};

export function entitlementIsActive(entitlement?: RevenueCatEntitlement | null, now = Date.now()): boolean {
  if (!entitlement) return false;
  const grace = parseIsoDate(entitlement.grace_period_expires_date ?? undefined);
  if (grace && grace.getTime() > now) return true;
  const expires = parseIsoDate(entitlement.expires_date ?? undefined);
  if (!expires) return true;
  return expires.getTime() > now;
}

function subscriptionIsActive(
  subscription?: RevenueCatSubscription | null,
  now = Date.now(),
): boolean {
  if (!subscription) return false;
  if (subscription.refunded_at) return false;
  const grace = parseIsoDate(subscription.grace_period_expires_date ?? undefined);
  if (grace && grace.getTime() > now) return true;
  const expires = parseIsoDate(subscription.expires_date ?? undefined);
  if (!expires) return true;
  return expires.getTime() > now;
}

function resolveFromActiveSubscriptions(
  subscriptions?: Record<string, RevenueCatSubscription>,
): { isPro: boolean; proExpiresAt: string | null; planPurchased: string | null } | null {
  if (!subscriptions) return null;

  for (const productId of KNOWN_PRODUCT_IDS) {
    const subscription = subscriptions[productId];
    if (!subscriptionIsActive(subscription)) continue;
    return {
      isPro: true,
      proExpiresAt: subscription?.expires_date ?? subscription?.grace_period_expires_date ?? null,
      planPurchased: planFromProductId(productId),
    };
  }

  for (const [key, subscription] of Object.entries(subscriptions)) {
    const productId = planFromProductId(key)
      ? key
      : subscription.product_identifier ?? null;
    if (!planFromProductId(productId) || !subscriptionIsActive(subscription)) continue;
    return {
      isPro: true,
      proExpiresAt: subscription.expires_date ?? subscription.grace_period_expires_date ?? null,
      planPurchased: planFromProductId(productId),
    };
  }

  return null;
}

function resolveFromEntitlementsByProduct(
  entitlements?: Record<string, RevenueCatEntitlement>,
): { isPro: boolean; proExpiresAt: string | null; planPurchased: string | null } | null {
  if (!entitlements) return null;

  for (const entitlement of Object.values(entitlements)) {
    if (!entitlementIsActive(entitlement)) continue;
    const planPurchased = planFromProductId(entitlement.product_identifier);
    if (!planPurchased) continue;
    return {
      isPro: true,
      proExpiresAt: entitlement.expires_date ?? entitlement.grace_period_expires_date ?? null,
      planPurchased,
    };
  }

  return null;
}

export function buildResolveDiagnostics(
  subscriber: RevenueCatSubscriberResponse["subscriber"],
  resolvedFrom: RevenueCatResolveDiagnostics["resolvedFrom"],
): RevenueCatResolveDiagnostics {
  return {
    entitlementKeys: Object.keys(subscriber?.entitlements ?? {}),
    subscriptionKeys: Object.keys(subscriber?.subscriptions ?? {}),
    originalAppUserId: subscriber?.original_app_user_id ?? null,
    resolvedFrom,
  };
}

/** Align with iOS: premium entitlement → any active VIP product entitlement → subscriptions. */
export function resolveEntitlementState(
  subscriber: RevenueCatSubscriberResponse["subscriber"],
): {
  isPro: boolean;
  proExpiresAt: string | null;
  planPurchased: string | null;
  diagnostics: RevenueCatResolveDiagnostics;
} {
  const inactive = {
    isPro: false,
    proExpiresAt: null,
    planPurchased: null,
    diagnostics: buildResolveDiagnostics(subscriber, "none"),
  };

  const entitlement = subscriber?.entitlements?.[REVENUECAT_ENTITLEMENT_ID];
  if (entitlementIsActive(entitlement)) {
    return {
      isPro: true,
      proExpiresAt: entitlement?.expires_date ?? entitlement?.grace_period_expires_date ?? null,
      planPurchased: planFromProductId(entitlement?.product_identifier),
      diagnostics: buildResolveDiagnostics(subscriber, "premium_entitlement"),
    };
  }

  const fromEntitlementProduct = resolveFromEntitlementsByProduct(subscriber?.entitlements);
  if (fromEntitlementProduct) {
    return {
      ...fromEntitlementProduct,
      diagnostics: buildResolveDiagnostics(subscriber, "entitlement_product"),
    };
  }

  const fromSubscriptions = resolveFromActiveSubscriptions(subscriber?.subscriptions);
  if (fromSubscriptions) {
    return {
      ...fromSubscriptions,
      diagnostics: buildResolveDiagnostics(subscriber, "subscription"),
    };
  }

  return inactive;
}

export function normalizeAppUserId(userId: string): string {
  return userId.trim().toLowerCase();
}

/** Auth user lookup with fallback to aliased anonymous / sibling App User IDs. */
export type LocalEntitlementHint = {
  isPro?: boolean;
  proExpiresAt?: string | null;
  productId?: string | null;
};

export function validateLocalEntitlementHint(
  hint?: LocalEntitlementHint | null,
  now = Date.now(),
): boolean {
  if (!hint?.isPro) return false;
  const expires = parseIsoDate(hint.proExpiresAt ?? undefined);
  if (expires && expires.getTime() <= now) return false;
  if (hint.productId && !planFromProductId(hint.productId)) return false;
  return true;
}

export async function resolveSubscriberForAuthUser(
  authUserId: string,
  secretApiKey: string,
  extraAliasIds: string[] = [],
): Promise<{
  isPro: boolean;
  proExpiresAt: string | null;
  planPurchased: string | null;
  diagnostics: RevenueCatResolveDiagnostics;
  resolvedFromAppUserId: string;
}> {
  const normalizedAuthId = normalizeAppUserId(authUserId);
  const primary = await fetchRevenueCatSubscriber(normalizedAuthId, secretApiKey);
  let state = resolveEntitlementState(primary.subscriber);

  if (state.isPro) {
    return { ...state, resolvedFromAppUserId: normalizedAuthId };
  }

  const aliasCandidates = new Set<string>();
  const original = primary.subscriber?.original_app_user_id?.trim();
  if (original && original !== normalizedAuthId) {
    aliasCandidates.add(original);
  }
  for (const alias of primary.subscriber?.aliases ?? []) {
    const trimmed = alias?.trim();
    if (trimmed && trimmed !== normalizedAuthId) {
      aliasCandidates.add(trimmed);
    }
  }
  for (const alias of extraAliasIds) {
    const trimmed = alias?.trim();
    if (trimmed && trimmed !== normalizedAuthId) {
      aliasCandidates.add(trimmed);
    }
  }

  for (const candidate of aliasCandidates) {
    const aliasResponse = await fetchRevenueCatSubscriber(candidate, secretApiKey);
    const aliasState = resolveEntitlementState(aliasResponse.subscriber);
    if (!aliasState.isPro) continue;

    console.info("resolveSubscriberForAuthUser: resolved via alias", {
      authUserId: normalizedAuthId,
      resolvedFromAppUserId: candidate,
      resolvedFrom: aliasState.diagnostics.resolvedFrom,
    });

    return {
      ...aliasState,
      resolvedFromAppUserId: candidate,
    };
  }

  return { ...state, resolvedFromAppUserId: normalizedAuthId };
}

export async function fetchRevenueCatSubscriber(
  appUserId: string,
  secretApiKey: string,
): Promise<RevenueCatSubscriberResponse> {
  const trimmedKey = secretApiKey.trim();
  if (trimmedKey.startsWith("appl_")) {
    throw new Error(
      "REVENUECAT_SECRET_API_KEY must be sk_... (Secret API Key), not appl_... (Public API Key)",
    );
  }

  const normalizedId = normalizeAppUserId(appUserId);
  // Secret API Key: do NOT send X-Platform (RevenueCat 403 / code 7243 if set).
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(normalizedId)}`,
    {
      headers: {
        Authorization: `Bearer ${trimmedKey}`,
        "Content-Type": "application/json",
      },
    },
  );

  const bodyText = await response.text();
  if (!response.ok) {
    throw new Error(`RevenueCat API ${response.status}: ${bodyText}`);
  }

  return JSON.parse(bodyText) as RevenueCatSubscriberResponse;
}

export const REVENUECAT_ACTIVATE_EVENTS = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED",
]);

export const REVENUECAT_DEACTIVATE_EVENTS = new Set([
  "EXPIRATION",
  "BILLING_ISSUE",
]);
