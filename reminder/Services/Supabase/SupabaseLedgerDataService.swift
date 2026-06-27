import Foundation

#if canImport(Supabase)
import Supabase

private enum LedgerSupabaseTable {
    static let expenseCategories = "expense_categories"
    static let pointsLedger = "points_ledger"
    static let tasks = "tasks"
}

final class SupabaseLedgerDataService: LedgerDataService {
    private let provider: SupabaseProvider

    init(provider: SupabaseProvider) {
        self.provider = provider
    }

    func fetchCategories(in householdId: UUID) async throws -> [ExpenseCategory] {
        try await provider.client
            .from(LedgerSupabaseTable.expenseCategories)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())
            .order("created_at")
            .execute()
            .value
    }

    func ensureDefaultCategories(in householdId: UUID) async throws -> [ExpenseCategory] {
        let existing = try await fetchCategories(in: householdId)
        if existing.isEmpty == false {
            return existing
        }

        let now = Date()
        let seeds = ExpenseCategory.defaultSeedTemplates.map { template in
            ExpenseCategory(
                id: UUID(),
                householdId: householdId,
                name: template.name,
                icon: template.icon,
                createdAt: now
            )
        }

        _ = try await provider.client
            .from(LedgerSupabaseTable.expenseCategories)
            .insert(seeds)
            .execute()

        return try await fetchCategories(in: householdId)
    }

    func fetchPointsLedger(in householdId: UUID, targetProfileId: UUID?) async throws -> [PointsLedgerEntry] {
        var query = provider.client
            .from(LedgerSupabaseTable.pointsLedger)
            .select()
            .eq("household_id", value: householdId.uuidString.lowercased())

        if let targetProfileId {
            query = query.eq("target_profile_id", value: targetProfileId.uuidString.lowercased())
        }

        return try await query
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func insertPointsLedgerEntry(_ entry: PointsLedgerEntry) async throws -> PointsLedgerEntry {
        try await provider.client
            .from(LedgerSupabaseTable.pointsLedger)
            .insert(entry)
            .select()
            .single()
            .execute()
            .value
    }

    func createLedgerTask(_ task: FamilyTask) async throws -> FamilyTask {
        try await provider.client
            .from(LedgerSupabaseTable.tasks)
            .insert(task.sanitizedForPersistence())
            .select()
            .single()
            .execute()
            .value
    }
}

#else

final class SupabaseLedgerDataService: LedgerDataService {
    init(provider: SupabaseProvider) {
        _ = provider
    }

    func fetchCategories(in householdId: UUID) async throws -> [ExpenseCategory] {
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
    }

    func ensureDefaultCategories(in householdId: UUID) async throws -> [ExpenseCategory] {
        _ = householdId
        throw SupabaseServiceError.sdkUnavailable
    }

    func fetchPointsLedger(in householdId: UUID, targetProfileId: UUID?) async throws -> [PointsLedgerEntry] {
        _ = householdId
        _ = targetProfileId
        throw SupabaseServiceError.sdkUnavailable
    }

    func insertPointsLedgerEntry(_ entry: PointsLedgerEntry) async throws -> PointsLedgerEntry {
        _ = entry
        throw SupabaseServiceError.sdkUnavailable
    }

    func createLedgerTask(_ task: FamilyTask) async throws -> FamilyTask {
        _ = task
        throw SupabaseServiceError.sdkUnavailable
    }
}

#endif
