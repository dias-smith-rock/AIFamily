import { createClient } from "@/lib/supabase/client";
import type { HouseholdMembership, MembershipRole } from "@/lib/types";

export interface MembershipWithHousehold {
  id: string;
  household_id: string;
  user_id: string | null;
  profile_id: string | null;
  role: MembershipRole;
  status: string;
  household: {
    id: string;
    name: string;
    description: string | null;
  } | null;
}

export async function listMyMemberships(): Promise<MembershipWithHousehold[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("household_memberships")
    .select(
      `
      id,
      household_id,
      user_id,
      profile_id,
      role,
      status,
      household:households (
        id,
        name,
        description
      )
    `
    )
    .eq("status", "active")
    .order("created_at", { ascending: true });

  if (error) throw error;

  return (data ?? []).map((row) => {
    const householdRaw = (row as { household?: MembershipWithHousehold["household"] | MembershipWithHousehold["household"][] }).household;
    const household = Array.isArray(householdRaw) ? householdRaw[0] ?? null : householdRaw ?? null;
    return { ...row, household } as MembershipWithHousehold;
  });
}

/** RPC accepts only `p_name`; optional description is applied via households update. */
export async function createHousehold(
  name: string,
  description?: string | null
): Promise<string> {
  const supabase = createClient();
  const trimmed = name.trim();
  if (!trimmed) throw new Error("invalid_household_name");

  const { data, error } = await supabase.rpc("create_household_with_membership", {
    p_name: trimmed,
  });

  if (error) throw error;
  const householdId = data as string;

  if (description?.trim()) {
    const { error: updateError } = await supabase
      .from("households")
      .update({ description: description.trim() })
      .eq("id", householdId);
    if (updateError) throw updateError;
  }

  return householdId;
}

export async function joinHousehold(code: string): Promise<string> {
  const supabase = createClient();
  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();
  if (authError) throw authError;
  if (!user) throw new Error("unauthenticated");

  const { data, error } = await supabase.rpc("join_household_by_nonce", {
    p_nonce: code.trim(),
    p_user_id: user.id,
  });

  if (error) throw error;
  return data as string;
}

export async function leaveHousehold(householdId: string): Promise<boolean> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("leave_household", {
    p_household_id: householdId,
  });
  if (error) throw error;
  return data as boolean;
}

export async function disbandHousehold(
  householdId: string,
  expectedName: string
): Promise<boolean> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("disband_household", {
    p_household_id: householdId,
    p_expected_name: expectedName.trim(),
  });
  if (error) throw error;
  return data as boolean;
}

export async function ensureCurrentUserFamilyProfile(): Promise<string | null> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("ensure_current_user_family_profile");
  if (error) return null;
  return (data as string) ?? null;
}

/** Admin/creator: get or create a 6-char invite nonce for the household. */
export async function getOrCreateInviteNonce(
  householdId: string,
  creatorMembershipId: string
): Promise<string> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("get_or_create_invite_nonce", {
    p_household_id: householdId,
    p_creator_id: creatorMembershipId,
  });
  if (error) throw error;
  if (Array.isArray(data) && data[0]?.nonce) return String(data[0].nonce);
  if (data && typeof data === "object" && "nonce" in data) {
    return String((data as { nonce: string }).nonce);
  }
  throw new Error("invite_nonce_unavailable");
}

export type { HouseholdMembership };
