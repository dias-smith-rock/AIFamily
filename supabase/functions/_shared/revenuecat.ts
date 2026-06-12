export const REVENUECAT_ENTITLEMENT_ID = "premium";

export const PRODUCT_PLAN_MAP: Record<string, string> = {
  "wesync.vip.monthly": "pro_monthly",
  "wesync.vip.yearly": "pro_yearly",
};

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

export type RevenueCatSubscriberResponse = {
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement>;
  };
};

export function entitlementIsActive(entitlement?: RevenueCatEntitlement | null, now = Date.now()): boolean {
  if (!entitlement) return false;
  const grace = parseIsoDate(entitlement.grace_period_expires_date ?? undefined);
  if (grace && grace.getTime() > now) return true;
  const expires = parseIsoDate(entitlement.expires_date ?? undefined);
  if (!expires) return true;
  return expires.getTime() > now;
}

export function resolveEntitlementState(
  subscriber: RevenueCatSubscriberResponse["subscriber"],
): { isPro: boolean; proExpiresAt: string | null; planPurchased: string | null } {
  const entitlement = subscriber?.entitlements?.[REVENUECAT_ENTITLEMENT_ID];
  const isPro = entitlementIsActive(entitlement);
  const proExpiresAt = entitlement?.expires_date ?? entitlement?.grace_period_expires_date ?? null;
  const planPurchased = planFromProductId(entitlement?.product_identifier);
  return { isPro, proExpiresAt, planPurchased };
}

export async function fetchRevenueCatSubscriber(
  appUserId: string,
  secretApiKey: string,
): Promise<RevenueCatSubscriberResponse> {
  const response = await fetch(
    `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}`,
    {
      headers: {
        Authorization: `Bearer ${secretApiKey}`,
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
