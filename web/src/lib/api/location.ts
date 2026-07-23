import { createClient } from "@/lib/supabase/client";
import type { LocationPoint, LocationState } from "@/lib/types";

type LocationRow = Record<string, unknown>;

function mapLocationState(row: LocationRow): LocationState {
  return {
    entity_id: String(row.entity_id),
    household_id: String(row.household_id),
    locations: (row.locations as LocationPoint[]) ?? [],
    is_ghost: Boolean(row.is_ghost_mode ?? row.is_ghost),
    battery_level: (row.battery_level as number | null) ?? null,
    is_charging: (row.is_charging as boolean | null) ?? null,
    updated_at: String(row.updated_at),
  };
}

export async function fetchLocationStates(householdId: string): Promise<LocationState[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("location_states")
    .select("*")
    .eq("household_id", householdId)
    .order("updated_at", { ascending: false });

  if (error) throw error;
  return (data ?? []).map((row) => mapLocationState(row as LocationRow));
}

export interface PushLocationInput {
  entityId: string;
  householdId: string;
  lat: number;
  lng: number;
  recordedAt?: string;
  accuracy?: number | null;
  batteryLevel?: number | null;
  isCharging?: boolean | null;
  addressName?: string | null;
  minDistanceMeters?: number | null;
  minIntervalSeconds?: number | null;
}

export async function pushLocation(input: PushLocationInput): Promise<void> {
  const supabase = createClient();
  const locationPayload: Record<string, unknown> = {
    lat: input.lat,
    lng: input.lng,
    recorded_at: input.recordedAt ?? new Date().toISOString(),
  };

  if (input.accuracy != null) locationPayload.accuracy = input.accuracy;
  if (input.batteryLevel != null) locationPayload.battery_level = input.batteryLevel;
  if (input.isCharging != null) locationPayload.is_charging = input.isCharging;
  if (input.addressName) locationPayload.address_name = input.addressName;

  const { error } = await supabase.rpc("push_entity_location", {
    p_entity_id: input.entityId,
    p_household_id: input.householdId,
    p_new_location: locationPayload,
    p_min_distance_meters: input.minDistanceMeters ?? null,
    p_min_interval_seconds: input.minIntervalSeconds ?? null,
  });

  if (error) throw error;
}

export async function setGhostMode(entityId: string, isGhost: boolean): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("set_ghost_mode", {
    p_entity_id: entityId,
    p_is_ghost: isGhost,
  });
  if (error) throw error;
}
