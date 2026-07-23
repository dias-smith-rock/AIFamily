import { createClient } from "@/lib/supabase/client";
import type { FamilyProfile, HouseholdMembership, MembershipRole } from "@/lib/types";

type ProfileRow = Record<string, unknown>;
type MembershipRow = Record<string, unknown>;

function mapProfile(row: ProfileRow): FamilyProfile {
  return {
    id: String(row.id),
    household_id: (row.household_id as string | null) ?? null,
    user_id: (row.user_id as string | null) ?? null,
    display_name: String(row.display_name ?? row.name ?? ""),
    avatar_url: (row.avatar_url as string | null) ?? null,
    birthday: (row.birthday as string | null) ?? (row.birth_date as string | null) ?? null,
    notes: (row.notes as string | null) ?? null,
    is_virtual_user: row.user_id == null,
    created_at: String(row.created_at),
    updated_at: row.updated_at ? String(row.updated_at) : undefined,
  };
}

function mapMembership(row: MembershipRow): HouseholdMembership {
  return {
    id: String(row.id),
    household_id: String(row.household_id),
    user_id: (row.user_id as string | null) ?? null,
    profile_id: (row.profile_id as string | null) ?? null,
    role: row.role as MembershipRole,
    status: row.status as HouseholdMembership["status"],
    display_name: (row.nickname as string | null) ?? (row.display_name as string | null) ?? null,
    created_at: String(row.created_at),
  };
}

export interface RosterEntry {
  membership: HouseholdMembership;
  profile: FamilyProfile | null;
}

export async function fetchRoster(householdId: string): Promise<RosterEntry[]> {
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
      nickname,
      created_at,
      profile:family_profiles (
        id,
        household_id,
        user_id,
        name,
        avatar_url,
        birth_date,
        created_at,
        updated_at
      )
    `
    )
    .eq("household_id", householdId)
    .in("status", ["active", "archived", "inactive"])
    .order("created_at", { ascending: true });

  if (error) throw error;

  return (data ?? []).map((row) => {
    const membership = mapMembership(row as MembershipRow);
    const profileRaw = (row as { profile?: ProfileRow | ProfileRow[] | null }).profile;
    const profileRow = Array.isArray(profileRaw) ? profileRaw[0] : profileRaw;
    return {
      membership,
      profile: profileRow ? mapProfile(profileRow) : null,
    };
  });
}

export async function createVirtualProfile(
  householdId: string,
  displayName: string
): Promise<FamilyProfile> {
  const supabase = createClient();
  const payload = {
    household_id: householdId,
    user_id: null,
    name: displayName.trim(),
  };

  const { data, error } = await supabase
    .from("family_profiles")
    .insert(payload)
    .select("*")
    .single();

  if (error) throw error;
  return mapProfile(data as ProfileRow);
}

export interface UpdateProfileInput {
  displayName?: string;
  avatarUrl?: string | null;
  birthday?: string | null;
  notes?: string | null;
}

export async function updateProfile(
  profileId: string,
  patch: UpdateProfileInput
): Promise<FamilyProfile> {
  const supabase = createClient();
  const dbPatch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (patch.displayName !== undefined) dbPatch.name = patch.displayName.trim();
  if (patch.avatarUrl !== undefined) dbPatch.avatar_url = patch.avatarUrl;
  if (patch.birthday !== undefined) dbPatch.birth_date = patch.birthday;
  if (patch.notes !== undefined) dbPatch.notes = patch.notes;

  const { data, error } = await supabase
    .from("family_profiles")
    .update(dbPatch)
    .eq("id", profileId)
    .select("*")
    .single();

  if (error) throw error;
  return mapProfile(data as ProfileRow);
}

/** Only virtual profiles (user_id IS NULL) can be deleted per RLS. */
export async function deleteProfile(profileId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.from("family_profiles").delete().eq("id", profileId);
  if (error) throw error;
}

export async function updateMembershipRole(
  membershipId: string,
  role: MembershipRole
): Promise<HouseholdMembership> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("household_memberships")
    .update({ role, updated_at: new Date().toISOString() })
    .eq("id", membershipId)
    .select("*")
    .single();

  if (error) throw error;
  return mapMembership(data as MembershipRow);
}
