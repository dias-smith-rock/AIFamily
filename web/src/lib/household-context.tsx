"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { createClient } from "@/lib/supabase/client";
import {
  ensureCurrentUserFamilyProfile,
  listMyMemberships,
} from "@/lib/api/households";
import {
  detectLocale,
  LOCALE_STORAGE_KEY,
  PRODUCT_NAMES,
  type AppLocale,
} from "@/lib/i18n";
import type { AppSessionContext, MembershipRole } from "@/lib/types";

export const SELECTED_HOUSEHOLD_KEY = "wesync.selectedHouseholdId";

export interface HouseholdSummary {
  id: string;
  name: string;
  role: MembershipRole;
  membershipId: string;
  profileId: string | null;
}

interface HouseholdContextValue {
  session: AppSessionContext | null;
  households: HouseholdSummary[];
  locale: AppLocale;
  productName: string;
  loading: boolean;
  setLocale: (locale: AppLocale) => void;
  setSession: (session: AppSessionContext | null) => void;
  refreshHouseholds: () => Promise<void>;
  chooseHousehold: (householdId: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const HouseholdContext = createContext<HouseholdContextValue | null>(null);

function buildSession(
  authUserId: string,
  summary: HouseholdSummary
): AppSessionContext {
  return {
    authUserId,
    householdId: summary.id,
    membershipId: summary.membershipId,
    profileId: summary.profileId,
    role: summary.role,
    householdName: summary.name,
  };
}

export function HouseholdProvider({ children }: { children: ReactNode }) {
  const supabase = useMemo(() => createClient(), []);
  const [session, setSession] = useState<AppSessionContext | null>(null);
  const [households, setHouseholds] = useState<HouseholdSummary[]>([]);
  const [locale, setLocaleState] = useState<AppLocale>("en");
  const [loading, setLoading] = useState(true);

  const productName = PRODUCT_NAMES[locale];

  const setLocale = useCallback((next: AppLocale) => {
    setLocaleState(next);
    if (typeof window !== "undefined") {
      localStorage.setItem(LOCALE_STORAGE_KEY, next);
    }
  }, []);

  const refreshHouseholds = useCallback(async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser();

    if (!user) {
      setHouseholds([]);
      setSession(null);
      return;
    }

    await ensureCurrentUserFamilyProfile().catch(() => null);

    const memberships = await listMyMemberships();
    const summaries: HouseholdSummary[] = [];
    const seenHouseholdIds = new Set<string>();
    for (const m of memberships) {
      if (!m.household) continue;
      if (seenHouseholdIds.has(m.household_id)) continue;
      seenHouseholdIds.add(m.household_id);
      summaries.push({
        id: m.household_id,
        name: m.household.name ?? "Household",
        role: m.role,
        membershipId: m.id,
        profileId: m.profile_id,
      });
    }

    setHouseholds(summaries);

    const storedId =
      typeof window !== "undefined"
        ? localStorage.getItem(SELECTED_HOUSEHOLD_KEY)
        : null;
    const selected =
      summaries.find((h) => h.id === storedId) ?? summaries[0] ?? null;

    if (selected) {
      setSession(buildSession(user.id, selected));
      if (typeof window !== "undefined") {
        localStorage.setItem(SELECTED_HOUSEHOLD_KEY, selected.id);
      }
    } else {
      setSession(null);
    }
  }, [supabase]);

  const chooseHousehold = useCallback(
    async (householdId: string) => {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("unauthenticated");

      const selected = households.find((h) => h.id === householdId);
      if (!selected) throw new Error("household_not_found");

      setSession(buildSession(user.id, selected));
      if (typeof window !== "undefined") {
        localStorage.setItem(SELECTED_HOUSEHOLD_KEY, householdId);
      }
    },
    [households, supabase]
  );

  const signOut = useCallback(async () => {
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    setSession(null);
    setHouseholds([]);
    if (typeof window !== "undefined") {
      localStorage.removeItem(SELECTED_HOUSEHOLD_KEY);
    }
  }, [supabase]);

  useEffect(() => {
    const storedLocale =
      typeof window !== "undefined"
        ? (localStorage.getItem(LOCALE_STORAGE_KEY) as AppLocale | null)
        : null;
    setLocaleState(storedLocale ?? detectLocale());
  }, []);

  useEffect(() => {
    let cancelled = false;

    async function bootstrap() {
      setLoading(true);
      try {
        await refreshHouseholds();
      } finally {
        if (!cancelled) setLoading(false);
      }
    }

    bootstrap();

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange(() => {
      refreshHouseholds().catch(() => undefined);
    });

    return () => {
      cancelled = true;
      subscription.unsubscribe();
    };
  }, [refreshHouseholds, supabase.auth]);

  const value = useMemo<HouseholdContextValue>(
    () => ({
      session,
      households,
      locale,
      productName,
      loading,
      setLocale,
      setSession,
      refreshHouseholds,
      chooseHousehold,
      signOut,
    }),
    [
      session,
      households,
      locale,
      productName,
      loading,
      setLocale,
      refreshHouseholds,
      chooseHousehold,
      signOut,
    ]
  );

  return (
    <HouseholdContext.Provider value={value}>{children}</HouseholdContext.Provider>
  );
}

export function useHousehold(): HouseholdContextValue {
  const ctx = useContext(HouseholdContext);
  if (!ctx) {
    throw new Error("useHousehold must be used within HouseholdProvider");
  }
  return ctx;
}
