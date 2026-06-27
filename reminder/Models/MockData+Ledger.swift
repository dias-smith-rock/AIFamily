import Foundation

enum MockLedgerData {
    static let childProfileId = UUID(uuidString: "C3D4E5F6-A7B8-4901-C234-56789012CD03") ?? UUID()

    static let mockPointsEntries: [PointsLedgerEntry] = [
        PointsLedgerEntry(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111101") ?? UUID(),
            householdId: MockIDs.household,
            targetProfileId: childProfileId,
            amount: 20,
            description: "整理房间",
            createdAt: .mockISO("2026-06-01T10:00:00.000Z")
        ),
        PointsLedgerEntry(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111102") ?? UUID(),
            householdId: MockIDs.household,
            targetProfileId: childProfileId,
            amount: -10,
            description: "兑换棒棒糖",
            createdAt: .mockISO("2026-06-02T18:30:00.000Z")
        )
    ]

    static func mockLedgerTasks(householdId: UUID, creatorMembershipId: UUID) -> [FamilyTask] {
        let now = Date()
        return [
            FamilyTask(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222201") ?? UUID(),
                householdId: householdId,
                creatorId: creatorMembershipId,
                title: "超市采购",
                description: "周末家庭采购",
                status: .completed,
                priority: .normal,
                taskType: FamilyTask.ledgerExpenseTaskType,
                dueDate: now,
                isAllDay: true,
                actualAmount: 268.5,
                payerId: creatorMembershipId,
                expenseCategory: "🛒 场景采购",
                createdAt: .mockISO("2026-06-03T12:00:00.000Z"),
                updatedAt: .mockISO("2026-06-03T12:00:00.000Z")
            ),
            FamilyTask(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222202") ?? UUID(),
                householdId: householdId,
                creatorId: creatorMembershipId,
                title: "水电退款",
                status: .completed,
                priority: .normal,
                taskType: FamilyTask.ledgerIncomeTaskType,
                dueDate: now,
                isAllDay: true,
                actualAmount: 120,
                payerId: creatorMembershipId,
                expenseCategory: "🏡 房屋物业",
                createdAt: .mockISO("2026-06-04T09:00:00.000Z"),
                updatedAt: .mockISO("2026-06-04T09:00:00.000Z")
            )
        ]
    }
}

extension FamilyTask {
    static var mockLedgerTasks: [FamilyTask] {
        MockLedgerData.mockLedgerTasks(
            householdId: MockIDs.household,
            creatorMembershipId: UUID(uuidString: "8AC693C1-B0EE-4E44-A87A-EFC3A3A1A001") ?? UUID()
        )
    }
}
