export type MembershipRole = "creator" | "admin" | "member";
export type MembershipStatus = "active" | "pending" | "invited" | "left" | "removed";
export type TaskType = "scheduled" | "flexible";
export type TaskStatus =
  | "new"
  | "accepted"
  | "inProgress"
  | "completed"
  | "issue"
  | "failed"
  | "expired"
  | "cancelled";
export type LedgerEntryType = "expense" | "income";

export interface Household {
  id: string;
  name: string;
  description: string | null;
  created_at: string;
  updated_at?: string;
}

export interface HouseholdMembership {
  id: string;
  household_id: string;
  user_id: string | null;
  profile_id: string | null;
  role: MembershipRole;
  status: MembershipStatus;
  display_name?: string | null;
  created_at: string;
}

export interface FamilyProfile {
  id: string;
  household_id: string | null;
  user_id: string | null;
  display_name: string;
  avatar_url: string | null;
  birthday: string | null;
  notes: string | null;
  is_virtual_user?: boolean;
  created_at: string;
  updated_at?: string;
}

export interface FamilyTask {
  id: string;
  household_id: string;
  creator_id: string;
  title: string;
  notes: string | null;
  status: TaskStatus;
  task_type: TaskType;
  due_date: string | null;
  end_datetime: string | null;
  duration_minutes: number;
  is_all_day: boolean;
  involved_member_ids: string[] | null;
  target_profile_ids: string[] | null;
  recurrence_rule: string | null;
  recurrence_end_date: string | null;
  priority: number | null;
  estimated_cost: number | null;
  location_data: unknown | null;
  geofence: unknown | null;
  completion_location: unknown | null;
  source: string | null;
  created_at: string;
  updated_at: string;
}

export interface ExpenseCategory {
  id: string;
  household_id: string;
  type: LedgerEntryType;
  name: string;
  preset_key: string | null;
  icon: string;
  color_hex: string | null;
  is_preset: boolean;
  sort_order: number;
  is_deleted: boolean;
  created_at: string;
  updated_at: string;
}

export interface CategoryTag {
  id: string;
  category_id: string;
  household_id: string;
  name: string;
  preset_key: string | null;
  is_preset: boolean;
  is_deleted: boolean;
  created_at: string;
}

export interface LedgerTransaction {
  id: string;
  household_id: string;
  creator_id: string;
  type: LedgerEntryType;
  amount: number;
  currency: string;
  transaction_time: string;
  category_id: string | null;
  category_name_snapshot: string;
  category_icon_snapshot: string | null;
  payer_ids: string[];
  target_member_ids: string[];
  visible_member_ids: string[];
  note: string | null;
  attachment_urls: string[];
  source: string;
  created_at: string;
  updated_at: string;
}

export interface LocationPoint {
  lat: number;
  lng: number;
  recorded_at?: string;
  accuracy?: number | null;
}

export interface LocationState {
  entity_id: string;
  household_id: string;
  locations: LocationPoint[];
  is_ghost?: boolean;
  battery_level?: number | null;
  is_charging?: boolean | null;
  updated_at: string;
}

export interface AppSessionContext {
  authUserId: string;
  householdId: string;
  membershipId: string;
  profileId: string | null;
  role: MembershipRole;
  householdName: string;
}
