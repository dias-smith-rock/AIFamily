#if DEBUG
import CoreLocation
import Foundation

/// DEBUG 专用：创建 Mock 组织并向其写入日历 / 待办 / 账盘数据（走 Live Service）。
@MainActor
enum DebugMockDataSeeder {
    struct SeedResult: Sendable {
        var organizations: Int
        var organizationNames: [String]
        var scheduledTasks: Int
        var flexibleTodos: Int
        var overdueTodos: Int
        var completedTodos: Int
        var ledgerTransactions: Int
        var locationMembers: Int
        var locationPoints: Int
        var firstHouseholdId: UUID?
    }

    enum SeedError: LocalizedError {
        case missingHousehold
        case missingMembership
        case missingProfile
        case noLedgerCategories
        case failedToResolveCreatedHousehold(UUID)

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
            case .failedToResolveCreatedHousehold(let id):
                "Created household \(id.uuidString) was not found in joined list."
            }
        }
    }

    private static let mockOrganizationNames = [
        "[Mock] Sunrise Family",
        "[Mock] Bay Studio",
        "[Mock] Weekend Crew",
    ]

    private static let countPerWeekRange = 10...20
    private static let ledgerCountPerMonthRange = 10...20

    // MARK: - Public entry

    /// 新建 3 个组织，并为本月每个组织灌入：计划 10～20/周、Todos 10～20/周、记账 10～20/月。
    static func seedThreeOrganizationsWithCurrentMonthData(
        services: ReminderServiceContainer
    ) async throws -> SeedResult {
        let calendar = Calendar.current
        let now = Date()
        var aggregate = SeedResult(
            organizations: 0,
            organizationNames: [],
            scheduledTasks: 0,
            flexibleTodos: 0,
            overdueTodos: 0,
            completedTodos: 0,
            ledgerTransactions: 0,
            locationMembers: 0,
            locationPoints: 0,
            firstHouseholdId: nil
        )

        for (index, name) in mockOrganizationNames.enumerated() {
            let householdId = try await services.householdRoutingService.createHousehold(
                displayName: name,
                description: "DEBUG mock organization #\(index + 1)"
            )
            let context = try await resolveCreatedHouseholdContext(
                services: services,
                householdId: householdId
            )

            let orgResult = try await seedCurrentMonthContent(
                services: services,
                householdId: householdId,
                membershipId: context.membershipId,
                profileId: context.profileId,
                peerProfileId: context.profileId,
                calendar: calendar,
                now: now,
                includeLocation: index == 0
            )

            aggregate.organizations += 1
            aggregate.organizationNames.append(name)
            aggregate.scheduledTasks += orgResult.scheduledTasks
            aggregate.flexibleTodos += orgResult.flexibleTodos
            aggregate.overdueTodos += orgResult.overdueTodos
            aggregate.completedTodos += orgResult.completedTodos
            aggregate.ledgerTransactions += orgResult.ledgerTransactions
            aggregate.locationMembers += orgResult.locationMembers
            aggregate.locationPoints += orgResult.locationPoints
            if aggregate.firstHouseholdId == nil {
                aggregate.firstHouseholdId = householdId
            }
        }

        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
        NotificationCenter.default.post(name: .locationStatesDidChange, object: nil)

        return aggregate
    }

    /// 向当前家庭写入本月 Mock（不新建组织）；保留旧入口兼容。
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

        let orgResult = try await seedCurrentMonthContent(
            services: services,
            householdId: householdId,
            membershipId: membershipId,
            profileId: profileId,
            peerProfileId: peerProfileId,
            calendar: calendar,
            now: now,
            includeLocation: true
        )

        NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
        NotificationCenter.default.post(name: .ledgerDataDidChange, object: nil)
        NotificationCenter.default.post(name: .locationStatesDidChange, object: nil)

        return SeedResult(
            organizations: 0,
            organizationNames: [],
            scheduledTasks: orgResult.scheduledTasks,
            flexibleTodos: orgResult.flexibleTodos,
            overdueTodos: orgResult.overdueTodos,
            completedTodos: orgResult.completedTodos,
            ledgerTransactions: orgResult.ledgerTransactions,
            locationMembers: orgResult.locationMembers,
            locationPoints: orgResult.locationPoints,
            firstHouseholdId: householdId
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

    // MARK: - Per-org seed

    private struct OrgSeedCounts {
        var scheduledTasks: Int
        var flexibleTodos: Int
        var overdueTodos: Int
        var completedTodos: Int
        var ledgerTransactions: Int
        var locationMembers: Int
        var locationPoints: Int
    }

    private struct HouseholdContext {
        let membershipId: UUID
        let profileId: UUID
    }

    private static func resolveCreatedHouseholdContext(
        services: ReminderServiceContainer,
        householdId: UUID
    ) async throws -> HouseholdContext {
        let joined = try await services.householdRoutingService.fetchMyJoinedHouseholds()
        if let match = joined.first(where: { $0.householdId == householdId }),
           let profileId = match.profileId {
            return HouseholdContext(membershipId: match.id, profileId: profileId)
        }

        let memberships = try await services.membershipService.fetchMemberships(in: householdId)
        if let creator = memberships.first(where: { $0.parsedRole == .creator }),
           let profileId = creator.profileId {
            return HouseholdContext(membershipId: creator.id, profileId: profileId)
        }
        if let any = memberships.first, let profileId = any.profileId {
            return HouseholdContext(membershipId: any.id, profileId: profileId)
        }

        throw SeedError.failedToResolveCreatedHousehold(householdId)
    }

    private static func seedCurrentMonthContent(
        services: ReminderServiceContainer,
        householdId: UUID,
        membershipId: UUID,
        profileId: UUID,
        peerProfileId: UUID,
        calendar: Calendar,
        now: Date,
        includeLocation: Bool
    ) async throws -> OrgSeedCounts {
        var scheduledCount = 0
        for draft in scheduledTaskDraftsForCurrentMonth(
            householdId: householdId,
            membershipId: membershipId,
            profileId: profileId,
            calendar: calendar,
            now: now
        ) {
            _ = try await services.taskService.createTask(draft, geofence: nil)
            scheduledCount += 1
        }

        let todos = flexibleTodoDraftsForCurrentMonth(
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
        for draft in ledgerDraftsForCurrentMonth(
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

        var locationMembers = 0
        var locationPoints = 0
        if includeLocation {
            let locationSeed = try await seedSanJoseMemberLocations(
                services: services,
                householdId: householdId,
                primaryProfileId: profileId,
                candidateProfileIds: [peerProfileId]
            )
            locationMembers = locationSeed.members
            locationPoints = locationSeed.points
        }

        return OrgSeedCounts(
            scheduledTasks: scheduledCount,
            flexibleTodos: flexibleCount,
            overdueTodos: overdueCount,
            completedTodos: completedCount,
            ledgerTransactions: txCount,
            locationMembers: locationMembers,
            locationPoints: locationPoints
        )
    }

    // MARK: - Month / week helpers

    /// 与本月相交的自然周区间（裁剪到月内）。
    private static func weekRangesInCurrentMonth(
        calendar: Calendar,
        now: Date
    ) -> [(weekIndex: Int, start: Date, end: Date)] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }

        var ranges: [(Int, Date, Date)] = []
        var cursor = monthInterval.start
        var weekIndex = 0

        while cursor < monthInterval.end {
            guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: cursor) else { break }
            let clippedStart = max(weekInterval.start, monthInterval.start)
            let clippedEnd = min(weekInterval.end, monthInterval.end)
            if clippedStart < clippedEnd {
                ranges.append((weekIndex, clippedStart, clippedEnd))
                weekIndex += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 7, to: weekInterval.start),
                  next > cursor else { break }
            cursor = next
        }
        return ranges
    }

    private static func randomDay(
        in start: Date,
        end: Date,
        calendar: Calendar
    ) -> Date {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end.addingTimeInterval(-1))
        let daySpan = max(calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0, 0)
        let offset = Int.random(in: 0...daySpan)
        return calendar.date(byAdding: .day, value: offset, to: startDay) ?? startDay
    }

    // MARK: - Calendar（本月，每周 10～20 条）

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
        "Piano lesson",
        "Budget review",
        "Park walk",
        "Car wash",
        "Movie night",
    ]

    private static let scheduleHours = [8, 9, 10, 11, 13, 14, 15, 16, 17, 19, 20]

    private static func scheduledTaskDraftsForCurrentMonth(
        householdId: UUID,
        membershipId: UUID,
        profileId: UUID,
        calendar: Calendar,
        now: Date
    ) -> [FamilyTask] {
        let stamp = now
        var drafts: [FamilyTask] = []
        let weeks = weekRangesInCurrentMonth(calendar: calendar, now: now)

        for week in weeks {
            let count = Int.random(in: countPerWeekRange)
            for slot in 0..<count {
                let day = randomDay(in: week.start, end: week.end, calendar: calendar)
                let hour = scheduleHours[slot % scheduleHours.count]
                let minute = Int.random(in: 0...50)
                let start = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                let duration = [30, 45, 60, 90][slot % 4]
                let end = calendar.date(byAdding: .minute, value: duration, to: start) ?? start
                let title = scheduleTitlePool[(week.weekIndex * 31 + slot) % scheduleTitlePool.count]
                let status: TaskStatus = {
                    if start < now.addingTimeInterval(-86_400) { return .completed }
                    if start < now { return [.accepted, .inProgress, .completed].randomElement() ?? .accepted }
                    return [.new, .accepted].randomElement() ?? .new
                }()
                let priority: TaskPriority = {
                    switch slot % 5 {
                    case 0: .urgent
                    case 1: .high
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
                        title: "[Mock] \(title) · W\(week.weekIndex + 1) #\(slot + 1)",
                        description: "DEBUG mock schedule week \(week.weekIndex + 1), item \(slot + 1).",
                        status: status,
                        priority: priority,
                        taskType: TaskTypeKind.scheduled.rawValue,
                        dueDate: start,
                        endDatetime: end,
                        durationMinutes: duration,
                        isAllDay: false,
                        reminderOffsets: slot % 4 == 0 ? [15] : nil,
                        createdAt: stamp,
                        updatedAt: stamp
                    )
                )
            }
        }
        return drafts
    }

    // MARK: - Todos（本月，每周 10～20 条）

    private static let todoTitlePool: [String] = [
        "Buy art class materials",
        "Renew car insurance",
        "Book weekend camping",
        "Organize photo album",
        "Submit school form",
        "Pay parking ticket",
        "Return library books",
        "Call property manager",
        "Order birthday cake",
        "Replace air filter",
        "Update emergency contacts",
        "Donate unused clothes",
        "Backup phone photos",
        "Schedule HVAC service",
        "Refill prescriptions",
        "Plan grocery list",
        "Fix bike chain",
        "Reply to PTA email",
        "Pack travel documents",
        "Water indoor plants",
    ]

    private static func flexibleTodoDraftsForCurrentMonth(
        householdId: UUID,
        membershipId: UUID,
        profileId: UUID,
        calendar: Calendar,
        now: Date
    ) -> [FamilyTask] {
        let stamp = now
        var drafts: [FamilyTask] = []
        let weeks = weekRangesInCurrentMonth(calendar: calendar, now: now)

        for week in weeks {
            let count = Int.random(in: countPerWeekRange)
            for slot in 0..<count {
                let day = randomDay(in: week.start, end: week.end, calendar: calendar)
                let end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? day
                let title = todoTitlePool[(week.weekIndex * 37 + slot) % todoTitlePool.count]

                let status: TaskStatus
                let priority: TaskPriority
                if end < now {
                    // 约 40% 已完成，其余逾期
                    if slot % 5 < 2 {
                        status = .completed
                        priority = .normal
                    } else {
                        status = .new
                        priority = slot % 2 == 0 ? .urgent : .high
                    }
                } else {
                    status = slot % 4 == 0 ? .accepted : .new
                    priority = slot % 5 == 0 ? .high : .normal
                }

                drafts.append(
                    FamilyTask(
                        id: UUID(),
                        householdId: householdId,
                        creatorId: membershipId,
                        involvedMemberIds: [membershipId],
                        targetProfileIds: [profileId],
                        title: "[Mock] \(title) · W\(week.weekIndex + 1) #\(slot + 1)",
                        description: "DEBUG mock todo week \(week.weekIndex + 1), item \(slot + 1).",
                        status: status,
                        priority: priority,
                        taskType: TaskTypeKind.flexible.rawValue,
                        dueDate: nil,
                        endDatetime: end,
                        durationMinutes: 0,
                        isAllDay: false,
                        createdAt: stamp,
                        updatedAt: stamp
                    )
                )
            }
        }
        return drafts
    }

    // MARK: - Wallet（本月 10～20 条）

    private static func ledgerDraftsForCurrentMonth(
        householdId: UUID,
        creatorProfileId: UUID,
        peerProfileId: UUID,
        categories: [ExpenseCategory],
        tags: [CategoryTag],
        calendar: Calendar,
        now: Date
    ) -> [LedgerTransactionDraft] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }

        let activeCategories = categories
            .filter { $0.isDeleted == false }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard activeCategories.isEmpty == false else { return [] }

        func selectedTags(for categoryId: UUID, limit: Int) -> [CategoryTag] {
            Array(tags.filter { $0.categoryId == categoryId && $0.isDeleted == false }.prefix(limit))
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

        let count = Int.random(in: ledgerCountPerMonthRange)
        var drafts: [LedgerTransactionDraft] = []
        drafts.reserveCapacity(count)

        for entryIndex in 0..<count {
            let category = activeCategories[entryIndex % activeCategories.count]
            let day = randomDay(in: monthInterval.start, end: monthInterval.end, calendar: calendar)
            let hour = Int.random(in: 8...21)
            let minute = Int.random(in: 0...50)
            let time = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            let payer = entryIndex % 2 == 0 ? creatorProfileId : peerProfileId
            let targets: [UUID] = category.type == .income
                ? [creatorProfileId]
                : Array(Set([creatorProfileId, peerProfileId]))

            drafts.append(
                LedgerTransactionDraft(
                    householdId: householdId,
                    type: category.type,
                    amount: randomAmount(for: category.type),
                    currency: "CNY",
                    transactionTime: time,
                    category: category,
                    selectedTags: selectedTags(for: category.id, limit: 1),
                    payerIds: [payer],
                    targetMemberIds: targets,
                    visibleMemberIds: Array(Set([creatorProfileId, peerProfileId])),
                    note: "[Mock] \(category.name) #\(entryIndex + 1)",
                    creatorProfileId: creatorProfileId
                )
            )
        }
        return drafts
    }

    // MARK: - Location（圣何塞市区，2 人 × 3 点）

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

        applySanJoseAsCurrentDeviceLocation()
        return (members: targets.count, points: totalPoints)
    }

    private static func applySanJoseAsCurrentDeviceLocation() {
        let anchor = sanJoseMemberALocations[0]
        let coordinate = CLLocationCoordinate2D(latitude: anchor.lat, longitude: anchor.lng)
        SimulatorLocationSupport.activateDebugMockLocation(coordinate)
        LastKnownDeviceLocation.record(latitude: anchor.lat, longitude: anchor.lng)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}
#endif
