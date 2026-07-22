#if DEBUG
import CoreLocation
import Foundation

/// DEBUG 专用：向当前家庭写入日历 / 待办 / 账盘 Mock 数据（走 Live Service，非内存 Mock 容器）。
@MainActor
enum DebugMockDataSeeder {
    struct SeedResult: Sendable {
        var scheduledTasks: Int
        var flexibleTodos: Int
        var overdueTodos: Int
        var completedTodos: Int
        var ledgerTransactions: Int
        var locationMembers: Int
        var locationPoints: Int
    }

    enum SeedError: LocalizedError {
        case missingHousehold
        case missingMembership
        case missingProfile
        case noLedgerCategories

        var errorDescription: String? {
            switch self {
            case .missingHousehold:
                "No household selected."
            case .missingMembership:
                "No membership selected."
            case .missingProfile:
                "No profile selected."
            case .noLedgerCategories:
                "Ledger categories are empty after ensurePresetCategories."
            }
        }
    }

    /// 近一个月窗口：今天往前 15 天 + 往后 14 天（共 30 天）。
    private static let calendarDayOffsets = Array(-15...14)
    private static let schedulesPerDay = 5

    static func seedCalendarTodosAndWallet(
        services: ReminderServiceContainer,
        householdId: UUID?,
        membershipId: UUID?,
        profileId: UUID?,
        extraProfileIds: [UUID] = []
    ) async throws -> SeedResult {
        guard let householdId else { throw SeedError.missingHousehold }
        guard let membershipId else { throw SeedError.missingMembership }
        guard let profileId else { throw SeedError.missingProfile }

        let calendar = Calendar.current
        let now = Date()
        let peerProfileId = extraProfileIds.first(where: { $0 != profileId }) ?? profileId

        var scheduledCount = 0
        for draft in scheduledTaskDrafts(
            householdId: householdId,
            membershipId: membershipId,
            profileId: profileId,
            calendar: calendar,
            now: now
        ) {
            _ = try await services.taskService.createTask(draft, geofence: nil)
            scheduledCount += 1
        }

        let todos = flexibleTodoDrafts(
            householdId: householdId,
            membershipId: membershipId,
            profileId: profileId,
            calendar: calendar,
            now: now
        )
        var flexibleCount = 0
        var overdueCount = 0
        var completedCount = 0
        for draft in todos {
            _ = try await services.taskService.createTask(draft, geofence: nil)
            switch draft.status {
            case .completed:
                completedCount += 1
            case .new, .accepted, .inProgress, .issue, .failed, .expired, .cancelled:
                if let end = draft.endDatetime, end < now {
                    overdueCount += 1
                } else {
                    flexibleCount += 1
                }
            }
        }

        try await services.ledgerService.ensurePresetCategories(in: householdId)
        let categories = try await services.ledgerService.fetchCategories(
            in: householdId,
            type: nil,
            includeDeleted: false
        )
        guard categories.isEmpty == false else { throw SeedError.noLedgerCategories }

        let tags = try await services.ledgerService.fetchTags(
            in: householdId,
            categoryId: nil,
            includeDeleted: false
        )

        var txCount = 0
        for draft in ledgerDrafts(
            householdId: householdId,
            creatorProfileId: profileId,
            peerProfileId: peerProfileId,
            categories: categories,
            tags: tags,
            calendar: calendar,
            now: now
        ) {
            _ = try await services.ledgerService.createTransaction(draft)
            txCount += 1
        }

        let locationSeed = try await seedSanJoseMemberLocations(
            services: services,
            householdId: householdId,
            primaryProfileId: profileId,
            candidateProfileIds: extraProfileIds
        )

        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
        NotificationCenter.default.post(name: .locationStatesDidChange, object: nil)

        return SeedResult(
            scheduledTasks: scheduledCount,
            flexibleTodos: flexibleCount,
            overdueTodos: overdueCount,
            completedTodos: completedCount,
            ledgerTransactions: txCount,
            locationMembers: locationSeed.members,
            locationPoints: locationSeed.points
        )
    }

    /// 仅灌圣何塞市区位置：2 名成员 × 各 3 点。
    static func seedSanJoseLocationsOnly(
        services: ReminderServiceContainer,
        householdId: UUID?,
        profileId: UUID?,
        extraProfileIds: [UUID] = []
    ) async throws -> (members: Int, points: Int) {
        guard let householdId else { throw SeedError.missingHousehold }
        guard let profileId else { throw SeedError.missingProfile }
        let result = try await seedSanJoseMemberLocations(
            services: services,
            householdId: householdId,
            primaryProfileId: profileId,
            candidateProfileIds: extraProfileIds
        )
        NotificationCenter.default.post(name: .locationStatesDidChange, object: nil)
        return result
    }

    // MARK: - Location（圣何塞市区，2 人 × 3 点）

    /// San Jose downtown 附近真实坐标（newest-first 写入顺序：最新点在前）。
    private static let sanJoseMemberALocations: [(lat: Double, lng: Double, name: String)] = [
        (37.3352, -121.8811, "San Pedro Square"),
        (37.3337, -121.8890, "Plaza de Cesar Chavez"),
        (37.3382, -121.8863, "San Jose Museum of Art"),
    ]

    private static let sanJoseMemberBLocations: [(lat: Double, lng: Double, name: String)] = [
        (37.3327, -121.9010, "SAP Center"),
        (37.3299, -121.9026, "Diridon Station"),
        (37.3305, -121.8887, "San Jose Convention Center"),
    ]

    private static func seedSanJoseMemberLocations(
        services: ReminderServiceContainer,
        householdId: UUID,
        primaryProfileId: UUID,
        candidateProfileIds: [UUID]
    ) async throws -> (members: Int, points: Int) {
        var targets: [UUID] = [primaryProfileId]
        if let peer = candidateProfileIds.first(where: { $0 != primaryProfileId }) {
            targets.append(peer)
        } else {
            // 只有一人时仍写两套轨迹到同一 profile 没有意义；再试一次重复 primary 不合适。
            // 若家庭只有一个 profile，只灌 1 人 × 3 点。
        }
        targets = Array(targets.prefix(2))

        let trails = [sanJoseMemberALocations, sanJoseMemberBLocations]
        var totalPoints = 0
        let now = Date()

        for (index, profileId) in targets.enumerated() {
            let trail = trails[index]
            let payloads: [LocationPayload] = trail.enumerated().map { pointIndex, point in
                let recordedAt = now.addingTimeInterval(TimeInterval(-pointIndex * 12 * 60))
                return LocationPayload(
                    latitude: point.lat,
                    longitude: point.lng,
                    addressName: "[Mock] \(point.name)",
                    recordedAt: recordedAt,
                    batteryLevel: 70 + (pointIndex * 8),
                    isCharging: pointIndex == 0
                )
            }
            try await services.locationStateService.replaceLocationsForDebug(
                householdId: householdId,
                profileId: profileId,
                locations: payloads,
                isGhostMode: false
            )
            totalPoints += payloads.count
        }

        // 当前用户「设备位置」也锚到圣何塞市区（模拟器不再夹回香港）。
        applySanJoseAsCurrentDeviceLocation()

        return (members: targets.count, points: totalPoints)
    }

    private static func applySanJoseAsCurrentDeviceLocation() {
        let anchor = sanJoseMemberALocations[0]
        let coordinate = CLLocationCoordinate2D(latitude: anchor.lat, longitude: anchor.lng)
        SimulatorLocationSupport.activateDebugMockLocation(coordinate)
        LastKnownDeviceLocation.record(latitude: anchor.lat, longitude: anchor.lng)
    }

    // MARK: - Calendar（近一个月，每天 5 条）

    private static let scheduleTitlePool: [String] = [
        "School pickup",
        "Dentist visit",
        "Team standup",
        "Grocery run",
        "Swim class",
        "Parent meeting",
        "Doctor checkup",
        "Homework review",
        "Family dinner",
        "Utility payment",
        "Library visit",
        "Soccer practice",
        "Online class",
        "Package pickup",
        "House cleaning",
    ]

    private static let scheduleHours = [8, 10, 13, 16, 19]

    private static func scheduledTaskDrafts(
        householdId: UUID,
        membershipId: UUID,
        profileId: UUID,
        calendar: Calendar,
        now: Date
    ) -> [FamilyTask] {
        let dayStart = calendar.startOfDay(for: now)
        let stamp = now
        var drafts: [FamilyTask] = []
        drafts.reserveCapacity(calendarDayOffsets.count * schedulesPerDay)

        for dayOffset in calendarDayOffsets {
            for slot in 0..<schedulesPerDay {
                let hour = scheduleHours[slot % scheduleHours.count]
                let minute = (slot * 7) % 50
                let baseDay = calendar.date(byAdding: .day, value: dayOffset, to: dayStart) ?? dayStart
                let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: baseDay) ?? baseDay
                let end = calendar.date(byAdding: .minute, value: 45, to: start) ?? start
                let titleIndex = abs(dayOffset * schedulesPerDay + slot) % scheduleTitlePool.count
                let title = scheduleTitlePool[titleIndex]
                let status: TaskStatus = {
                    if dayOffset < -1 { return .completed }
                    if dayOffset == -1, slot < 3 { return .completed }
                    if dayOffset == 0, slot == 0 { return .accepted }
                    return .new
                }()
                let priority: TaskPriority = {
                    switch slot {
                    case 0: .high
                    case 1: .urgent
                    default: .normal
                    }
                }()

                drafts.append(
                    FamilyTask(
                        id: UUID(),
                        householdId: householdId,
                        creatorId: membershipId,
                        involvedMemberIds: [membershipId],
                        targetProfileIds: [profileId],
                        title: "[Mock] \(title) · D\(dayOffset) #\(slot + 1)",
                        description: "DEBUG mock schedule for day offset \(dayOffset), slot \(slot + 1).",
                        status: status,
                        priority: priority,
                        taskType: TaskTypeKind.scheduled.rawValue,
                        dueDate: start,
                        endDatetime: end,
                        durationMinutes: 45,
                        isAllDay: false,
                        reminderOffsets: slot == 0 ? [15] : nil,
                        createdAt: stamp,
                        updatedAt: stamp
                    )
                )
            }
        }
        return drafts
    }

    // MARK: - Todos（4 条进行中 + 4 条逾期 + 5 条已完成）

    private static func flexibleTodoDrafts(
        householdId: UUID,
        membershipId: UUID,
        profileId: UUID,
        calendar: Calendar,
        now: Date
    ) -> [FamilyTask] {
        let dayStart = calendar.startOfDay(for: now)
        func endOfDay(offset: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: offset, to: dayStart) ?? dayStart
            return calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
        }

        let stamp = now
        let activeTitles = [
            "Buy art class materials",
            "Renew car insurance",
            "Book weekend camping",
            "Organize photo album",
        ]
        let overdueTitles = [
            "Submit school form",
            "Pay parking ticket",
            "Return library books",
            "Call property manager",
        ]
        let completedTitles = [
            "Order birthday cake",
            "Replace air filter",
            "Update emergency contacts",
            "Donate unused clothes",
            "Backup phone photos",
        ]

        var drafts: [FamilyTask] = []

        for (index, title) in activeTitles.enumerated() {
            drafts.append(
                FamilyTask(
                    id: UUID(),
                    householdId: householdId,
                    creatorId: membershipId,
                    involvedMemberIds: [membershipId],
                    targetProfileIds: [profileId],
                    title: "[Mock] \(title)",
                    description: "Active flexible todo #\(index + 1).",
                    status: index == 0 ? .accepted : .new,
                    priority: index == 0 ? .high : .normal,
                    taskType: TaskTypeKind.flexible.rawValue,
                    dueDate: nil,
                    endDatetime: endOfDay(offset: 3 + index * 4),
                    durationMinutes: 0,
                    isAllDay: false,
                    createdAt: stamp,
                    updatedAt: stamp
                )
            )
        }

        for (index, title) in overdueTitles.enumerated() {
            drafts.append(
                FamilyTask(
                    id: UUID(),
                    householdId: householdId,
                    creatorId: membershipId,
                    involvedMemberIds: [membershipId],
                    targetProfileIds: [profileId],
                    title: "[Mock] \(title)",
                    description: "Overdue flexible todo #\(index + 1).",
                    status: .new,
                    priority: index < 2 ? .urgent : .high,
                    taskType: TaskTypeKind.flexible.rawValue,
                    dueDate: nil,
                    endDatetime: endOfDay(offset: -(1 + index)),
                    durationMinutes: 0,
                    isAllDay: false,
                    createdAt: stamp,
                    updatedAt: stamp
                )
            )
        }

        for (index, title) in completedTitles.enumerated() {
            drafts.append(
                FamilyTask(
                    id: UUID(),
                    householdId: householdId,
                    creatorId: membershipId,
                    involvedMemberIds: [membershipId],
                    targetProfileIds: [profileId],
                    title: "[Mock] \(title)",
                    description: "Completed flexible todo #\(index + 1).",
                    status: .completed,
                    priority: .normal,
                    taskType: TaskTypeKind.flexible.rawValue,
                    dueDate: nil,
                    endDatetime: endOfDay(offset: -(3 + index)),
                    durationMinutes: 0,
                    isAllDay: false,
                    createdAt: stamp,
                    updatedAt: stamp
                )
            )
        }

        return drafts
    }

    // MARK: - Wallet（每个分类 2 条，金额随机）

    private static func ledgerDrafts(
        householdId: UUID,
        creatorProfileId: UUID,
        peerProfileId: UUID,
        categories: [ExpenseCategory],
        tags: [CategoryTag],
        calendar: Calendar,
        now: Date
    ) -> [LedgerTransactionDraft] {
        func selectedTags(for categoryId: UUID, limit: Int) -> [CategoryTag] {
            Array(tags.filter { $0.categoryId == categoryId && $0.isDeleted == false }.prefix(limit))
        }

        func day(offset: Int, hour: Int) -> Date {
            let base = calendar.startOfDay(for: now)
            let day = calendar.date(byAdding: .day, value: offset, to: base) ?? base
            return calendar.date(bySettingHour: hour, minute: Int.random(in: 0...50), second: 0, of: day) ?? day
        }

        func randomAmount(for type: LedgerEntryType) -> Double {
            switch type {
            case .expense:
                let major = Double(Int.random(in: 8...420))
                let cents = Double(Int.random(in: 0...99)) / 100
                return (major + cents).rounded(toPlaces: 2)
            case .income:
                let major = Double(Int.random(in: 50...12000))
                let cents = Double(Int.random(in: 0...99)) / 100
                return (major + cents).rounded(toPlaces: 2)
            }
        }

        let activeCategories = categories
            .filter { $0.isDeleted == false }
            .sorted { $0.sortOrder < $1.sortOrder }

        var drafts: [LedgerTransactionDraft] = []
        drafts.reserveCapacity(activeCategories.count * 2)

        for (categoryIndex, category) in activeCategories.enumerated() {
            for entryIndex in 0..<2 {
                let dayOffset = -((categoryIndex * 2 + entryIndex) % 28)
                let payer = entryIndex == 0 ? creatorProfileId : peerProfileId
                let targets: [UUID] = category.type == .income
                    ? [creatorProfileId]
                    : [creatorProfileId, peerProfileId]
                drafts.append(
                    LedgerTransactionDraft(
                        householdId: householdId,
                        type: category.type,
                        amount: randomAmount(for: category.type),
                        currency: "CNY",
                        transactionTime: day(offset: dayOffset, hour: 9 + entryIndex * 5),
                        category: category,
                        selectedTags: selectedTags(for: category.id, limit: 1),
                        payerIds: [payer],
                        targetMemberIds: targets,
                        visibleMemberIds: [creatorProfileId, peerProfileId],
                        note: "[Mock] \(category.name) #\(entryIndex + 1)",
                        creatorProfileId: creatorProfileId
                    )
                )
            }
        }
        return drafts
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
#endif
