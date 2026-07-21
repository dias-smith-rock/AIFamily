import Foundation

enum MockLedgerData {
    struct SeedBundle {
        let categories: [ExpenseCategory]
        let tags: [CategoryTag]
        let transactions: [LedgerTransaction]
        let mappings: [TransactionTagMapping]
    }

    static let diningCategoryId = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA01") ?? UUID()
    static let incomeCategoryId = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAA02") ?? UUID()
    static let breakfastTagId = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBB01") ?? UUID()
    static let dadProfileId = UUID(uuidString: "A1B2C3D4-E5F6-4789-A012-34567890AB01") ?? UUID()
    static let childProfileId = UUID(uuidString: "C3D4E5F6-A7B8-4901-C234-56789012CD03") ?? UUID()

    static func seedBundle(householdId: UUID) -> SeedBundle {
        let now = Date()
        let dining = ExpenseCategory(
            id: diningCategoryId,
            householdId: householdId,
            type: .expense,
            name: "Dining",
            presetKey: "cat_dining",
            icon: "🍔",
            colorHex: "#FF9500",
            isPreset: true,
            sortOrder: 1,
            isDeleted: false,
            createdAt: now,
            updatedAt: now
        )
        let income = ExpenseCategory(
            id: incomeCategoryId,
            householdId: householdId,
            type: .income,
            name: "Salary & Income",
            presetKey: "cat_income",
            icon: "💼",
            colorHex: "#34C759",
            isPreset: true,
            sortOrder: 1,
            isDeleted: false,
            createdAt: now,
            updatedAt: now
        )
        let breakfast = CategoryTag(
            id: breakfastTagId,
            categoryId: diningCategoryId,
            householdId: householdId,
            name: "Breakfast",
            presetKey: "tag_breakfast",
            isPreset: true,
            isDeleted: false,
            createdAt: now
        )
        let txId = UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCC01") ?? UUID()
        let expense = LedgerTransaction(
            id: txId,
            householdId: householdId,
            creatorId: dadProfileId,
            type: .expense,
            amount: 86.5,
            currency: "HKD",
            transactionTime: .mockISO("2026-06-20T08:30:00.000Z"),
            categoryId: diningCategoryId,
            categoryNameSnapshot: "Dining",
            categoryIconSnapshot: "🍔",
            payerIds: [dadProfileId],
            targetMemberIds: [childProfileId],
            visibleMemberIds: [dadProfileId],
            note: "Weekend dim sum",
            attachmentUrls: [],
            source: "manual",
            createdAt: .mockISO("2026-06-20T08:30:00.000Z"),
            updatedAt: .mockISO("2026-06-20T08:30:00.000Z"),
            tagSnapshots: ["Breakfast"]
        )
        let incomeTx = LedgerTransaction(
            id: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCC02") ?? UUID(),
            householdId: householdId,
            creatorId: dadProfileId,
            type: .income,
            amount: 1200,
            currency: "HKD",
            transactionTime: .mockISO("2026-06-01T09:00:00.000Z"),
            categoryId: incomeCategoryId,
            categoryNameSnapshot: "Salary & Income",
            categoryIconSnapshot: "💼",
            payerIds: [dadProfileId],
            targetMemberIds: [],
            visibleMemberIds: [dadProfileId],
            note: nil,
            attachmentUrls: [],
            source: "manual",
            createdAt: .mockISO("2026-06-01T09:00:00.000Z"),
            updatedAt: .mockISO("2026-06-01T09:00:00.000Z")
        )
        let mapping = TransactionTagMapping(
            transactionId: txId,
            tagId: breakfastTagId,
            tagNameSnapshot: "Breakfast",
            createdAt: now
        )
        return SeedBundle(
            categories: [dining, income],
            tags: [breakfast],
            transactions: [expense, incomeTx],
            mappings: [mapping]
        )
    }
}
