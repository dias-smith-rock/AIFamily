import { createClient } from "@/lib/supabase/client";
import type {
  CategoryTag,
  ExpenseCategory,
  LedgerEntryType,
  LedgerTransaction,
} from "@/lib/types";

type CategoryRow = Record<string, unknown>;
type TagRow = Record<string, unknown>;
type TransactionRow = Record<string, unknown>;

function mapCategory(row: CategoryRow): ExpenseCategory {
  return {
    id: String(row.id),
    household_id: String(row.household_id),
    type: row.type as LedgerEntryType,
    name: String(row.name),
    preset_key: (row.preset_key as string | null) ?? null,
    icon: String(row.icon ?? "💰"),
    color_hex: (row.color_hex as string | null) ?? null,
    is_preset: Boolean(row.is_preset),
    sort_order: Number(row.sort_order ?? 100),
    is_deleted: Boolean(row.is_deleted),
    created_at: String(row.created_at),
    updated_at: String(row.updated_at ?? row.created_at),
  };
}

function mapTag(row: TagRow): CategoryTag {
  return {
    id: String(row.id),
    category_id: String(row.category_id),
    household_id: String(row.household_id),
    name: String(row.name),
    preset_key: (row.preset_key as string | null) ?? null,
    is_preset: Boolean(row.is_preset),
    is_deleted: Boolean(row.is_deleted),
    created_at: String(row.created_at),
  };
}

function mapTransaction(row: TransactionRow): LedgerTransaction {
  const payerIds = row.payer_ids as string[] | undefined;
  const legacyPayer = row.payer_id as string | null | undefined;

  return {
    id: String(row.id),
    household_id: String(row.household_id),
    creator_id: String(row.creator_id),
    type: row.type as LedgerEntryType,
    amount: Number(row.amount),
    currency: String(row.currency ?? "HKD"),
    transaction_time: String(row.transaction_time),
    category_id: (row.category_id as string | null) ?? null,
    category_name_snapshot: String(row.category_name_snapshot),
    category_icon_snapshot: (row.category_icon_snapshot as string | null) ?? null,
    payer_ids:
      payerIds && payerIds.length > 0
        ? payerIds
        : legacyPayer
          ? [legacyPayer]
          : [],
    target_member_ids: (row.target_member_ids as string[]) ?? [],
    visible_member_ids: (row.visible_member_ids as string[]) ?? [],
    note: (row.note as string | null) ?? null,
    attachment_urls: (row.attachment_urls as string[]) ?? [],
    source: String(row.source ?? "manual"),
    created_at: String(row.created_at),
    updated_at: String(row.updated_at),
  };
}

export async function ensurePresets(householdId: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.rpc("ensure_household_ledger_presets", {
    p_household_id: householdId,
  });
  // 预设补种失败不阻断账本主流程（可能已有分类或 RPC 暂不可用）
  if (error) {
    console.warn("[ledger] ensure_household_ledger_presets:", error.message);
  }
}

export async function fetchCategories(householdId: string): Promise<ExpenseCategory[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("expense_categories")
    .select("*")
    .eq("household_id", householdId)
    .eq("is_deleted", false)
    .order("sort_order", { ascending: true });

  if (error) throw error;
  return (data ?? []).map((row) => mapCategory(row as CategoryRow));
}

export async function fetchTags(householdId: string): Promise<CategoryTag[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("category_tags")
    .select("*")
    .eq("household_id", householdId)
    .eq("is_deleted", false)
    .order("created_at", { ascending: true });

  if (error) throw error;
  return (data ?? []).map((row) => mapTag(row as TagRow));
}

export async function fetchTransactions(householdId: string): Promise<LedgerTransaction[]> {
  const supabase = createClient();
  const { data, error } = await supabase
    .from("ledger_transactions")
    .select("*")
    .eq("household_id", householdId)
    .order("transaction_time", { ascending: false });

  if (error) throw error;
  return (data ?? []).map((row) => mapTransaction(row as TransactionRow));
}

export interface CreateTransactionInput {
  householdId: string;
  creatorProfileId: string;
  type: LedgerEntryType;
  amount: number;
  currency?: string;
  transactionTime?: string;
  categoryId?: string | null;
  categoryNameSnapshot: string;
  categoryIconSnapshot?: string | null;
  payerIds?: string[];
  targetMemberIds?: string[];
  visibleMemberIds?: string[];
  note?: string | null;
  attachmentUrls?: string[];
  source?: string;
}

export async function createTransaction(
  input: CreateTransactionInput
): Promise<LedgerTransaction> {
  const supabase = createClient();
  const payload = {
    household_id: input.householdId,
    creator_id: input.creatorProfileId,
    type: input.type,
    amount: input.amount,
    currency: input.currency ?? "HKD",
    transaction_time: input.transactionTime ?? new Date().toISOString(),
    category_id: input.categoryId ?? null,
    category_name_snapshot: input.categoryNameSnapshot,
    category_icon_snapshot: input.categoryIconSnapshot ?? null,
    payer_ids: input.payerIds ?? [],
    target_member_ids: input.targetMemberIds ?? [],
    visible_member_ids: input.visibleMemberIds ?? [],
    note: input.note ?? null,
    attachment_urls: input.attachmentUrls ?? [],
    source: input.source ?? "manual",
  };

  const { data, error } = await supabase
    .from("ledger_transactions")
    .insert(payload)
    .select("*")
    .single();

  if (error) throw error;
  return mapTransaction(data as TransactionRow);
}

export async function updateTransaction(
  id: string,
  patch: Partial<CreateTransactionInput>
): Promise<LedgerTransaction> {
  const supabase = createClient();
  const dbPatch: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  };

  if (patch.type !== undefined) dbPatch.type = patch.type;
  if (patch.amount !== undefined) dbPatch.amount = patch.amount;
  if (patch.currency !== undefined) dbPatch.currency = patch.currency;
  if (patch.transactionTime !== undefined) dbPatch.transaction_time = patch.transactionTime;
  if (patch.categoryId !== undefined) dbPatch.category_id = patch.categoryId;
  if (patch.categoryNameSnapshot !== undefined) {
    dbPatch.category_name_snapshot = patch.categoryNameSnapshot;
  }
  if (patch.categoryIconSnapshot !== undefined) {
    dbPatch.category_icon_snapshot = patch.categoryIconSnapshot;
  }
  if (patch.payerIds !== undefined) dbPatch.payer_ids = patch.payerIds;
  if (patch.targetMemberIds !== undefined) dbPatch.target_member_ids = patch.targetMemberIds;
  if (patch.visibleMemberIds !== undefined) dbPatch.visible_member_ids = patch.visibleMemberIds;
  if (patch.note !== undefined) dbPatch.note = patch.note;
  if (patch.attachmentUrls !== undefined) dbPatch.attachment_urls = patch.attachmentUrls;
  if (patch.source !== undefined) dbPatch.source = patch.source;

  const { data, error } = await supabase
    .from("ledger_transactions")
    .update(dbPatch)
    .eq("id", id)
    .select("*")
    .single();

  if (error) throw error;
  return mapTransaction(data as TransactionRow);
}

export async function deleteTransaction(id: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.from("ledger_transactions").delete().eq("id", id);
  if (error) throw error;
}

export interface CreateCategoryInput {
  householdId: string;
  type: LedgerEntryType;
  name: string;
  icon?: string;
  colorHex?: string | null;
  sortOrder?: number;
}

export async function createCategory(input: CreateCategoryInput): Promise<ExpenseCategory> {
  const supabase = createClient();
  const payload = {
    household_id: input.householdId,
    type: input.type,
    name: input.name.trim(),
    icon: input.icon ?? "💰",
    color_hex: input.colorHex ?? "#007AFF",
    is_preset: false,
    sort_order: input.sortOrder ?? 100,
    is_deleted: false,
  };

  const { data, error } = await supabase
    .from("expense_categories")
    .insert(payload)
    .select("*")
    .single();

  if (error) throw error;
  return mapCategory(data as CategoryRow);
}

export async function updateCategory(
  id: string,
  patch: Partial<CreateCategoryInput>
): Promise<ExpenseCategory> {
  const supabase = createClient();
  const dbPatch: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (patch.name !== undefined) dbPatch.name = patch.name.trim();
  if (patch.icon !== undefined) dbPatch.icon = patch.icon;
  if (patch.colorHex !== undefined) dbPatch.color_hex = patch.colorHex;
  if (patch.sortOrder !== undefined) dbPatch.sort_order = patch.sortOrder;
  if (patch.type !== undefined) dbPatch.type = patch.type;

  const { data, error } = await supabase
    .from("expense_categories")
    .update(dbPatch)
    .eq("id", id)
    .select("*")
    .single();

  if (error) throw error;
  return mapCategory(data as CategoryRow);
}

export async function softDeleteCategory(id: string): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase
    .from("expense_categories")
    .update({ is_deleted: true, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

export async function updateSortOrders(
  orders: { id: string; sortOrder: number }[]
): Promise<void> {
  const supabase = createClient();
  const now = new Date().toISOString();

  const results = await Promise.all(
    orders.map(({ id, sortOrder }) =>
      supabase
        .from("expense_categories")
        .update({ sort_order: sortOrder, updated_at: now })
        .eq("id", id)
    )
  );

  const failed = results.find((r) => r.error);
  if (failed?.error) throw failed.error;
}
