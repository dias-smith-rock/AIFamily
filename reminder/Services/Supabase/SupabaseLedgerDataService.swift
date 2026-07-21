import Foundation

#if canImport(Supabase)
import Supabase

private enum LedgerSupabaseTable {
    static let expenseCategories = "expense_categories"
    static let categoryTags = "category_tags"
    static let ledgerTransactions = "ledger_transactions"
    static let transactionTagMappings = "transaction_tag_mappings"
}

final class SupabaseLedgerDataService: LedgerDataService {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func fetchCategories(
        in householdId: UUID,
        type: LedgerEntryType?,
        includeDeleted: Bool
    ) async throws -> [ExpenseCategory] {
        var query = provider.client
            .from(LedgerSupabaseTable.expenseCategories)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())

        if includeDeleted == false {
            query = query.eq("is_deleted", value: false)
        }
        if let type {
            query = query.eq("type", value: type.rawValue)
        }

        return try await query
            .order("sort_order")
            .order("created_at")
            .execute()
            .value
    }

    func fetchTags(
        in householdId: UUID,
        categoryId: UUID?,
        includeDeleted: Bool
    ) async throws -> [CategoryTag] {
        var query = provider.client
            .from(LedgerSupabaseTable.categoryTags)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())

        if includeDeleted == false {
            query = query.eq("is_deleted", value: false)
        }
        if let categoryId {
            query = query.eq("category_id", value: categoryId.uuidString.lowercased())
        }

        return try await query
            .order("created_at")
            .execute()
            .value
    }

    func fetchTransactions(in householdId: UUID) async throws -> [LedgerTransaction] {
        try await provider.client
            .from(LedgerSupabaseTable.ledgerTransactions)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .order("transaction_time", ascending: false)
            .execute()
            .value
    }

    func fetchTagMappings(for transactionIds: [UUID]) async throws -> [TransactionTagMapping] {
        guard transactionIds.isEmpty == false else { return [] }
        let ids = transactionIds.map { $0.uuidString.lowercased() }
        return try await provider.client
            .from(LedgerSupabaseTable.transactionTagMappings)
            .select()
            .in("transaction_id", values: ids)
            .execute()
            .value
    }

    func createTransaction(_ draft: LedgerTransactionDraft) async throws -> LedgerTransaction {
        let now = Date()
        let transaction = LedgerTransaction(
            id: UUID(),
            householdId: draft.householdId,
            creatorId: draft.creatorProfileId,
            type: draft.type,
            amount: draft.amount,
            currency: draft.currency,
            transactionTime: draft.transactionTime,
            categoryId: draft.category.id,
            categoryNameSnapshot: draft.category.name,
            categoryIconSnapshot: draft.category.icon,
            payerId: draft.payerId,
            targetMemberIds: draft.targetMemberIds,
            note: draft.note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            attachmentUrls: [],
            source: "manual",
            createdAt: now,
            updatedAt: now
        )

        let created: LedgerTransaction = try await provider.client
            .from(LedgerSupabaseTable.ledgerTransactions)
            .insert(transaction)
            .select()
            .single()
            .execute()
            .value

        if draft.selectedTags.isEmpty == false {
            let mappings = draft.selectedTags.map { tag in
                TransactionTagMapping(
                    transactionId: created.id,
                    tagId: tag.id,
                    tagNameSnapshot: tag.name,
                    createdAt: now
                )
            }
            _ = try await provider.client
                .from(LedgerSupabaseTable.transactionTagMappings)
                .insert(mappings)
                .execute()
        }

        var result = created
        result.tagSnapshots = draft.selectedTags.map(\.name)
        return result
    }

    func softDeleteCategory(id: UUID) async throws {
        LedgerCategoryDeleteLogger.step(
            .serviceStarted,
            categoryId: id,
            detail: "table=expense_categories patch=is_deleted,updated_at"
        )
        do {
            let patch = CategorySoftDeletePatch(isDeleted: true, updatedAt: Date())
            let updated: ExpenseCategory = try await provider.client
                .from(LedgerSupabaseTable.expenseCategories)
                .update(patch)
                .eq("id", value: id.uuidString.lowercased())
                .select()
                .single()
                .execute()
                .value
            LedgerCategoryDeleteLogger.step(
                .updateReturned,
                categoryId: id,
                categoryName: updated.name,
                householdId: updated.householdId,
                detail: "is_deleted=\(updated.isDeleted) type=\(updated.type.rawValue) is_preset=\(updated.isPreset)"
            )
            guard updated.isDeleted else {
                throw LedgerCategoryMutationError.softDeleteDidNotPersist
            }

            let tagPatch = TagSoftDeletePatch(isDeleted: true)
            _ = try await provider.client
                .from(LedgerSupabaseTable.categoryTags)
                .update(tagPatch)
                .eq("category_id", value: id.uuidString.lowercased())
                .eq("is_deleted", value: false)
                .execute()
            LedgerCategoryDeleteLogger.step(
                .tagsSoftDeleted,
                categoryId: id,
                householdId: updated.householdId
            )
        } catch {
            LedgerCategoryDeleteLogger.failure(
                step: .failed,
                error: error,
                categoryId: id,
                detail: "phase=supabase_update"
            )
            throw error
        }
    }

    func softDeleteTag(id: UUID) async throws {
        let patch = TagSoftDeletePatch(isDeleted: true)
        let updated: CategoryTag = try await provider.client
            .from(LedgerSupabaseTable.categoryTags)
            .update(patch)
            .eq("id", value: id.uuidString.lowercased())
            .select()
            .single()
            .execute()
            .value
        guard updated.isDeleted else {
            throw LedgerCategoryMutationError.softDeleteDidNotPersist
        }
    }

    func createCategory(
        householdId: UUID,
        type: LedgerEntryType,
        name: String,
        icon: String,
        colorHex: String?
    ) async throws -> ExpenseCategory {
        let now = Date()
        let row = ExpenseCategory(
            id: UUID(),
            householdId: householdId,
            type: type,
            name: name,
            presetKey: nil,
            icon: icon,
            colorHex: colorHex ?? "#007AFF",
            isPreset: false,
            sortOrder: 100,
            isDeleted: false,
            createdAt: now,
            updatedAt: now
        )
        return try await provider.client
            .from(LedgerSupabaseTable.expenseCategories)
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    func updateCategory(
        id: UUID,
        name: String,
        icon: String,
        colorHex: String?
    ) async throws -> ExpenseCategory {
        let patch = CategoryUpdatePatch(
            name: name,
            icon: icon,
            colorHex: colorHex,
            updatedAt: Date()
        )
        return try await provider.client
            .from(LedgerSupabaseTable.expenseCategories)
            .update(patch)
            .eq("id", value: id.uuidString.lowercased())
            .select()
            .single()
            .execute()
            .value
    }

    func createTag(householdId: UUID, categoryId: UUID, name: String) async throws -> CategoryTag {
        let row = CategoryTag(
            id: UUID(),
            categoryId: categoryId,
            householdId: householdId,
            name: name,
            presetKey: nil,
            isPreset: false,
            isDeleted: false,
            createdAt: Date()
        )
        return try await provider.client
            .from(LedgerSupabaseTable.categoryTags)
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    func ensurePresetCategories(in householdId: UUID) async throws {
        let params = EnsureHouseholdLedgerPresetsParams(householdId: householdId)
        try await provider.client
            .rpc("ensure_household_ledger_presets", params: params)
            .execute()
    }
}

private struct EnsureHouseholdLedgerPresetsParams: Encodable, Sendable {
    let householdId: UUID

    enum CodingKeys: String, CodingKey {
        case householdId = "p_household_id"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#else

final class SupabaseLedgerDataService: LedgerDataService {
    init(provider: SupabaseProvider) {
        _ = provider
    }

    func fetchCategories(in householdId: UUID, type: LedgerEntryType?, includeDeleted: Bool) async throws -> [ExpenseCategory] {
        _ = householdId; _ = type; _ = includeDeleted
        throw SupabaseServiceError.sdkUnavailable
    }

    func fetchTags(in householdId: UUID, categoryId: UUID?, includeDeleted: Bool) async throws -> [CategoryTag] {
        _ = householdId; _ = categoryId; _ = includeDeleted
        throw SupabaseServiceError.sdkUnavailable
    }

    func fetchTransactions(in householdId: UUID) async throws -> [LedgerTransaction] {
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
    }

    func fetchTagMappings(for transactionIds: [UUID]) async throws -> [TransactionTagMapping] {
        _ = transactionIds
        throw SupabaseServiceError.sdkUnavailable
    }

    func createTransaction(_ draft: LedgerTransactionDraft) async throws -> LedgerTransaction {
        _ = draft
        throw SupabaseServiceError.sdkUnavailable
    }

    func softDeleteCategory(id: UUID) async throws {
        _ = id
        throw SupabaseServiceError.sdkUnavailable
    }

    func softDeleteTag(id: UUID) async throws {
        _ = id
        throw SupabaseServiceError.sdkUnavailable
    }

    func createCategory(
        householdId: UUID,
        type: LedgerEntryType,
        name: String,
        icon: String,
        colorHex: String?
    ) async throws -> ExpenseCategory {
        _ = householdId; _ = type; _ = name; _ = icon; _ = colorHex
        throw SupabaseServiceError.sdkUnavailable
    }

    func updateCategory(
        id: UUID,
        name: String,
        icon: String,
        colorHex: String?
    ) async throws -> ExpenseCategory {
        _ = id; _ = name; _ = icon; _ = colorHex
        throw SupabaseServiceError.sdkUnavailable
    }

    func createTag(householdId: UUID, categoryId: UUID, name: String) async throws -> CategoryTag {
        _ = householdId; _ = categoryId; _ = name
        throw SupabaseServiceError.sdkUnavailable
    }

    func ensurePresetCategories(in householdId: UUID) async throws {
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
    }
}

#endif
