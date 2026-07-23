import { createClient } from "@/lib/supabase/client";

export interface TaskAttachment {
  id: string;
  task_id: string;
  file_url: string;
  file_type: string;
  file_size_bytes: number | null;
  created_by: string | null;
  created_at: string | null;
}

const BUCKET = "task_attachments";
const FREE_MAX = 1;
const PRO_MAX = 10;

export function maxAttachments(hasPremium: boolean): number {
  return hasPremium ? PRO_MAX : FREE_MAX;
}

export async function fetchAttachments(taskId: string): Promise<TaskAttachment[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("task_attachments")
    .select("id, task_id, file_url, file_type, file_size_bytes, created_by, created_at")
    .eq("task_id", taskId)
    .order("created_at", { ascending: true });

  if (error) throw error;
  return (data ?? []) as TaskAttachment[];
}

export async function uploadTaskAttachments(
  taskId: string,
  householdId: string,
  files: File[],
  options?: { hasPremium?: boolean; existingCount?: number }
): Promise<TaskAttachment[]> {
  if (files.length === 0) return [];

  const limit = maxAttachments(options?.hasPremium ?? false);
  const existing = options?.existingCount ?? 0;
  const room = Math.max(0, limit - existing);
  if (room <= 0) {
    throw new Error(`Attachment limit reached (${limit}). Upgrade Pro for more.`);
  }

  const toUpload = files.slice(0, room);
  const supabase = createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("unauthenticated");

  const userFolder = user.id.toLowerCase();
  const householdFolder = householdId.toLowerCase();
  const uploaded: { file_url: string; file_type: string; file_size_bytes: number }[] = [];

  for (const file of toUpload) {
    const ext = file.name.split(".").pop()?.toLowerCase() || "jpg";
    const fileName = `${crypto.randomUUID()}.${ext}`;
    const candidates = [
      `${userFolder}/${fileName}`,
      `${householdFolder}/${fileName}`,
      fileName,
    ];

    let publicUrl: string | null = null;
    let lastError: Error | null = null;

    for (const path of candidates) {
      const { error: uploadError } = await supabase.storage
        .from(BUCKET)
        .upload(path, file, {
          contentType: file.type || "image/jpeg",
          upsert: false,
        });
      if (uploadError) {
        lastError = uploadError;
        continue;
      }
      const { data } = supabase.storage.from(BUCKET).getPublicUrl(path);
      publicUrl = data.publicUrl;
      break;
    }

    if (!publicUrl) {
      throw lastError ?? new Error("upload_failed");
    }

    uploaded.push({
      file_url: publicUrl,
      file_type: file.type || "image/jpeg",
      file_size_bytes: file.size,
    });
  }

  const rows = uploaded.map((u) => ({
    task_id: taskId,
    file_url: u.file_url,
    file_type: u.file_type,
    file_size_bytes: u.file_size_bytes,
  }));

  const { data, error } = await supabase
    .from("task_attachments")
    .insert(rows)
    .select("id, task_id, file_url, file_type, file_size_bytes, created_by, created_at");

  if (error) throw error;
  return (data ?? []) as TaskAttachment[];
}

export async function deleteAttachments(ids: string[]): Promise<void> {
  if (ids.length === 0) return;
  const supabase = createClient();
  const { error } = await supabase.from("task_attachments").delete().in("id", ids);
  if (error) throw error;
}
