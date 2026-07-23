import { createClient } from "@/lib/supabase/client";
import type { FamilyTask, TaskStatus, TaskType } from "@/lib/types";

type TaskRow = Record<string, unknown>;

function mapTaskRow(row: TaskRow): FamilyTask {
  return {
    id: String(row.id),
    household_id: String(row.household_id),
    creator_id: String(row.creator_id),
    title: String(row.title),
    notes: (row.description as string | null) ?? (row.notes as string | null) ?? null,
    status: row.status as TaskStatus,
    task_type: (row.task_type as TaskType) ?? "scheduled",
    due_date: (row.due_date as string | null) ?? null,
    end_datetime: (row.end_datetime as string | null) ?? null,
    duration_minutes: Number(row.duration_minutes ?? 60),
    is_all_day: Boolean(row.is_all_day),
    involved_member_ids: (row.involved_member_ids as string[] | null) ?? null,
    target_profile_ids: (row.target_profile_ids as string[] | null) ?? null,
    recurrence_rule: (row.recurrence_rule as string | null) ?? null,
    recurrence_end_date: (row.recurrence_end_date as string | null) ?? null,
    priority: row.priority != null ? Number(row.priority) : null,
    estimated_cost: row.estimated_cost != null ? Number(row.estimated_cost) : null,
    location_data: row.location_data ?? null,
    geofence: row.geofence ?? null,
    completion_location: row.completion_location ?? null,
    source: (row.source as string | null) ?? null,
    created_at: String(row.created_at),
    updated_at: String(row.updated_at),
  };
}

function isMissingSpatialRpc(error: { message?: string }): boolean {
  const haystack = (error.message ?? "").toLowerCase();
  return (
    haystack.includes("create_task_with_spatial") ||
    haystack.includes("complete_task_with_spatial")
  ) && haystack.includes("schema cache");
}

export interface CreateTaskInput {
  householdId: string;
  creatorMembershipId: string;
  title: string;
  notes?: string | null;
  taskType?: TaskType;
  dueDate?: string | null;
  endDatetime?: string | null;
  durationMinutes?: number;
  isAllDay?: boolean;
  involvedMemberIds?: string[] | null;
  targetProfileIds?: string[] | null;
  geofence?: unknown | null;
  recurrenceRule?: string | null;
  recurrenceEndDate?: string | null;
  estimatedCost?: number | null;
}

export async function fetchTasks(householdId: string): Promise<FamilyTask[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("tasks")
    .select("*")
    .eq("household_id", householdId)
    .order("due_date", { ascending: true, nullsFirst: false })
    .order("created_at", { ascending: false });

  if (error) throw error;
  return (data ?? []).map((row) => mapTaskRow(row as TaskRow));
}

async function insertTaskFallback(input: CreateTaskInput): Promise<FamilyTask> {
  const supabase = createClient();
  const now = new Date().toISOString();
  const payload = {
    household_id: input.householdId,
    creator_id: input.creatorMembershipId,
    title: input.title.trim(),
    description: input.notes?.trim() ?? null,
    status: "new",
    priority: "normal",
    task_type: input.taskType ?? "scheduled",
    due_date: input.dueDate ?? null,
    end_datetime: input.endDatetime ?? null,
    duration_minutes: input.durationMinutes ?? 60,
    is_all_day: input.isAllDay ?? false,
    involved_member_ids: input.involvedMemberIds ?? null,
    target_profile_ids: input.targetProfileIds ?? null,
    geofence: input.geofence ?? null,
    recurrence_rule: input.recurrenceRule ?? null,
    recurrence_end_date: input.recurrenceEndDate ?? null,
    estimated_cost: input.estimatedCost ?? 0,
    source: "manual",
    created_at: now,
    updated_at: now,
  };

  const { data, error } = await supabase.from("tasks").insert(payload).select("*").single();
  if (error) throw error;
  return mapTaskRow(data as TaskRow);
}

async function createTaskViaRpc(input: CreateTaskInput): Promise<FamilyTask> {
  const supabase = createClient();
  const { data, error } = await supabase.rpc("create_task_with_spatial", {
    p_title: input.title.trim(),
    p_description: input.notes?.trim() ?? null,
    p_creator_id: input.creatorMembershipId,
    p_tenant_id: input.householdId,
    p_geofence: input.geofence ?? null,
  });

  if (error) throw error;

  let task = mapTaskRow(data as TaskRow);

  const patch: Record<string, unknown> = {};
  if (input.taskType && input.taskType !== task.task_type) patch.task_type = input.taskType;
  if (input.dueDate !== undefined) patch.due_date = input.dueDate;
  if (input.endDatetime !== undefined) patch.end_datetime = input.endDatetime;
  if (input.durationMinutes !== undefined) patch.duration_minutes = input.durationMinutes;
  if (input.isAllDay !== undefined) patch.is_all_day = input.isAllDay;
  if (input.involvedMemberIds !== undefined) patch.involved_member_ids = input.involvedMemberIds;
  if (input.targetProfileIds !== undefined) patch.target_profile_ids = input.targetProfileIds;
  if (input.recurrenceRule !== undefined) patch.recurrence_rule = input.recurrenceRule;
  if (input.recurrenceEndDate !== undefined) patch.recurrence_end_date = input.recurrenceEndDate;
  if (input.estimatedCost !== undefined) patch.estimated_cost = input.estimatedCost;

  if (Object.keys(patch).length > 0) {
    task = await updateTask(task.id, patch);
  }

  return task;
}

export async function createScheduledTask(input: CreateTaskInput): Promise<FamilyTask> {
  try {
    return await createTaskViaRpc({ ...input, taskType: "scheduled" });
  } catch (error) {
    if (error && typeof error === "object" && isMissingSpatialRpc(error as { message?: string })) {
      return insertTaskFallback({ ...input, taskType: "scheduled" });
    }
    throw error;
  }
}

export async function createFlexibleTask(input: CreateTaskInput): Promise<FamilyTask> {
  try {
    return await createTaskViaRpc({ ...input, taskType: "flexible" });
  } catch (error) {
    if (error && typeof error === "object" && isMissingSpatialRpc(error as { message?: string })) {
      return insertTaskFallback({ ...input, taskType: "flexible" });
    }
    throw error;
  }
}

export async function updateTask(
  id: string,
  patch: Record<string, unknown>
): Promise<FamilyTask> {
  const supabase = createClient();
  const dbPatch: Record<string, unknown> = {
    ...patch,
    updated_at: new Date().toISOString(),
  };
  if ("notes" in dbPatch) {
    dbPatch.description = dbPatch.notes;
    delete dbPatch.notes;
  }

  const { data, error } = await supabase
    .from("tasks")
    .update(dbPatch)
    .eq("id", id)
    .select("*")
    .single();

  if (error) throw error;
  return mapTaskRow(data as TaskRow);
}

export async function completeTask(
  id: string,
  membershipId: string,
  completionLocation?: unknown | null
): Promise<FamilyTask> {
  const supabase = createClient();
  try {
    const { data, error } = await supabase.rpc("complete_task_with_spatial", {
      p_task_id: id,
      p_user_id: membershipId,
      p_completion_location: completionLocation ?? null,
    });
    if (error) throw error;
    return mapTaskRow(data as TaskRow);
  } catch (error) {
    if (error && typeof error === "object" && isMissingSpatialRpc(error as { message?: string })) {
      return patchStatus(id, "completed");
    }
    throw error;
  }
}

export async function deleteTask(id: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.from("tasks").delete().eq("id", id);
  if (error) throw error;
}

export async function patchStatus(id: string, status: TaskStatus): Promise<FamilyTask> {
  return updateTask(id, { status });
}
