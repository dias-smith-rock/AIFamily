import Foundation

// MARK: - Date Helpers

extension Date {
    static func mockISO(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? Date()
    }
}

// MARK: - Shared Mock IDs

enum MockIDs {
    static let household = UUID(uuidString: "F0E1D2C3-B4A5-4968-9F8E-7A6B5C4D3E2F") ?? UUID()
    static let creatorUserId = UUID(uuidString: "8AC693C1-B0EE-4E44-A87A-EFC3A3A11001") ?? UUID()
}

// MARK: - FamilyProfile Mock

extension FamilyProfile {
    static let mockProfiles: [FamilyProfile] = [
        FamilyProfile(
            id: UUID(uuidString: "A1B2C3D4-E5F6-4789-A012-34567890AB01") ?? UUID(),
            householdId: nil,
            name: "爸爸",
            userId: MockIDs.creatorUserId
        ),
        FamilyProfile(
            id: UUID(uuidString: "B2C3D4E5-F6A7-4890-B123-45678901BC02") ?? UUID(),
            householdId: nil,
            name: "妈妈",
            userId: UUID(uuidString: "1E4F2CE0-7F66-4B2D-8A0A-3C880D5AAA02")
        ),
        FamilyProfile(
            id: UUID(uuidString: "C3D4E5F6-A7B8-4901-C234-56789012CD03") ?? UUID(),
            householdId: MockIDs.household,
            name: "小宝",
            userId: nil
        ),
        FamilyProfile(
            id: UUID(uuidString: "D4E5F6A7-B8C9-4012-D345-67890123DE04") ?? UUID(),
            householdId: MockIDs.household,
            name: "奶奶",
            userId: nil
        ),
        FamilyProfile(
            id: UUID(uuidString: "E5F6A7B8-C9D0-4123-E456-78901234EF05") ?? UUID(),
            householdId: MockIDs.household,
            name: "保姆",
            userId: nil
        )
    ]
}

// MARK: - HouseholdMembership Mock

extension HouseholdMembership {
    static let mockMembers: [HouseholdMembership] = [
        HouseholdMembership(
            id: UUID(uuidString: "8AC693C1-B0EE-4E44-A87A-EFC3A3A1A001") ?? UUID(),
            householdId: MockIDs.household,
            userId: MockIDs.creatorUserId,
            profileId: UUID(uuidString: "A1B2C3D4-E5F6-4789-A012-34567890AB01"),
            role: .creator,
            nickname: "爸爸",
            status: .active,
            joinedAt: .mockISO("2026-04-01T08:00:00.000Z"),
            createdAt: .mockISO("2026-04-01T08:00:00.000Z"),
            updatedAt: .mockISO("2026-04-27T08:30:00.000Z")
        ),
        HouseholdMembership(
            id: UUID(uuidString: "1E4F2CE0-7F66-4B2D-8A0A-3C880D5A4002") ?? UUID(),
            householdId: MockIDs.household,
            userId: UUID(uuidString: "1E4F2CE0-7F66-4B2D-8A0A-3C880D5AAA02") ?? UUID(),
            profileId: UUID(uuidString: "B2C3D4E5-F6A7-4890-B123-45678901BC02"),
            role: .admin,
            nickname: "妈妈",
            status: .active,
            joinedAt: .mockISO("2026-04-01T08:05:00.000Z"),
            createdAt: .mockISO("2026-04-01T08:05:00.000Z"),
            updatedAt: .mockISO("2026-04-27T08:32:00.000Z")
        ),
        HouseholdMembership(
            id: UUID(uuidString: "D9D43B14-CB56-4E4B-ABF7-6FAAA41F2003") ?? UUID(),
            householdId: MockIDs.household,
            userId: nil,
            profileId: UUID(uuidString: "D4E5F6A7-B8C9-4012-D345-67890123DE04"),
            role: .member,
            nickname: "奶奶",
            status: .active,
            joinedAt: .mockISO("2026-04-05T09:20:00.000Z"),
            createdAt: .mockISO("2026-04-05T09:20:00.000Z"),
            updatedAt: .mockISO("2026-04-27T07:45:00.000Z")
        ),
        HouseholdMembership(
            id: UUID(uuidString: "7D8B4FA4-EE8B-41E4-BB4A-2C67BB9E3004") ?? UUID(),
            householdId: MockIDs.household,
            userId: nil,
            profileId: UUID(uuidString: "E5F6A7B8-C9D0-4123-E456-78901234EF05"),
            role: .member,
            nickname: "保姆",
            status: .pending,
            joinedAt: nil,
            createdAt: .mockISO("2026-04-10T03:10:00.000Z"),
            updatedAt: .mockISO("2026-04-27T07:50:00.000Z")
        )
    ]
}

// MARK: - FamilyTask Mock

extension FamilyTask {
    static let mockChildProfileId = UUID(uuidString: "C3D4E5F6-A7B8-4901-C234-56789012CD03") ?? UUID()

    static let mockTasks: [FamilyTask] = [
        FamilyTask(
            id: UUID(uuidString: "A4795A12-72C1-49B6-88A2-2A6B47A51001") ?? UUID(),
            householdId: MockIDs.household,
            creatorId: HouseholdMembership.mockMembers[1].id,
            parentTaskId: nil,
            originalDueDate: .mockISO("2026-04-27T09:00:00.000Z"),
            involvedMemberIds: [HouseholdMembership.mockMembers[2].id],
            targetProfileIds: [mockChildProfileId],
            targetSubject: nil,
            title: AppLocalized.localizedSync(L10n.Common.takeCramSchool),
            description: "下课后先确认作业本是否带齐。",
            originalPrompt: "记得 17:00 接小明下补习班",
            attachmentUrls: nil,
            externalContacts: ["艺术中心前台": "010-66889900"],
            locationData: FamilyTask.LocationData(
                name: "艺术中心",
                address: "海淀区中关村南大街 18 号",
                latitude: 39.9786,
                longitude: 116.3164
            ),
            externalSyncRefs: nil,
            alarmSetBy: ["奶奶": FamilyTask.AlarmConfig(type: "phone_call", phone: "13700137000")],
            status: .completed,
            priority: .high,
            dueDate: .mockISO("2026-04-27T09:00:00.000Z"),
            isAllDay: false,
            recurrenceRule: nil,
            recurrenceEndDate: nil,
            recurrenceInterval: nil,
            reminderOffsets: [15, 5],
            estimatedCost: 0,
            createdAt: .mockISO("2026-04-27T02:00:00.000Z"),
            updatedAt: .mockISO("2026-04-27T09:20:00.000Z")
        ),
        FamilyTask(
            id: UUID(uuidString: "B55B6EA1-A357-46D2-B7E9-8B359E6D1002") ?? UUID(),
            householdId: MockIDs.household,
            creatorId: HouseholdMembership.mockMembers[0].id,
            parentTaskId: nil,
            originalDueDate: .mockISO("2026-04-27T10:30:00.000Z"),
            involvedMemberIds: [HouseholdMembership.mockMembers[3].id],
            targetProfileIds: [mockChildProfileId],
            targetSubject: nil,
            title: AppLocalized.localizedSync(L10n.Common.pickUpAndDropOffFromSchool),
            description: "17:20 前到校门口，避免晚高峰拥堵。",
            originalPrompt: nil,
            attachmentUrls: nil,
            externalContacts: nil,
            locationData: FamilyTask.LocationData(
                name: "学校门口",
                address: "海淀区学清路 38 号",
                latitude: nil,
                longitude: nil
            ),
            externalSyncRefs: ["ios": ["calendar_id": "C-IOS-001"]],
            alarmSetBy: nil,
            status: .new,
            priority: .urgent,
            dueDate: .mockISO("2026-04-27T10:30:00.000Z"),
            isAllDay: false,
            recurrenceRule: "FREQ=WEEKLY;BYDAY=MO,WE,FR",
            recurrenceEndDate: nil,
            recurrenceInterval: 1,
            reminderOffsets: [10],
            estimatedCost: 0,
            emergencyPhone: "138 0013 8000",
            createdAt: .mockISO("2026-04-27T03:20:00.000Z"),
            updatedAt: .mockISO("2026-04-27T03:20:00.000Z")
        ),
        FamilyTask(
            id: UUID(uuidString: "C82D9000-6AD8-4A68-9F84-4AE465BA1003") ?? UUID(),
            householdId: MockIDs.household,
            creatorId: HouseholdMembership.mockMembers[1].id,
            parentTaskId: nil,
            originalDueDate: .mockISO("2026-04-27T06:00:00.000Z"),
            involvedMemberIds: [HouseholdMembership.mockMembers[0].id],
            targetProfileIds: [mockChildProfileId],
            targetSubject: nil,
            title: AppLocalized.localizedSync(L10n.Common.physicalExaminationReview),
            description: "带医保卡、上次检查报告。",
            originalPrompt: "周一上午带小明去社区医院做体检复查",
            attachmentUrls: ["https://example.com/scan/medical-report.png"],
            externalContacts: ["社区医院前台": "010-12345678"],
            locationData: FamilyTask.LocationData(
                name: "社区医院",
                address: "朝阳区幸福里 12 号",
                latitude: 39.9512,
                longitude: 116.4502
            ),
            externalSyncRefs: nil,
            alarmSetBy: nil,
            status: .expired,
            priority: .high,
            dueDate: .mockISO("2026-04-27T06:00:00.000Z"),
            isAllDay: false,
            recurrenceRule: nil,
            recurrenceEndDate: nil,
            recurrenceInterval: nil,
            reminderOffsets: [30],
            estimatedCost: 200,
            createdAt: .mockISO("2026-04-26T14:10:00.000Z"),
            updatedAt: .mockISO("2026-04-27T06:30:00.000Z")
        ),
        FamilyTask(
            id: UUID(uuidString: "D1E2F3A4-B5C6-4789-AD01-23456789ABCD") ?? UUID(),
            householdId: MockIDs.household,
            creatorId: HouseholdMembership.mockMembers[0].id,
            parentTaskId: nil,
            involvedMemberIds: nil,
            targetProfileIds: [mockChildProfileId],
            targetSubject: nil,
            title: AppLocalized.localizedSync(L10n.Common.payArtClassMaterialFee),
            description: "本周五前完成缴费即可。",
            originalPrompt: nil,
            attachmentUrls: nil,
            externalContacts: nil,
            locationData: nil,
            externalSyncRefs: nil,
            alarmSetBy: nil,
            status: .new,
            priority: .normal,
            taskType: TaskTypeKind.flexible.rawValue,
            dueDate: nil,
            endDatetime: .mockISO("2026-05-30T00:00:00.000Z"),
            durationMinutes: 0,
            isAllDay: false,
            recurrenceRule: nil,
            recurrenceEndDate: nil,
            recurrenceInterval: nil,
            reminderOffsets: nil,
            estimatedCost: 0,
            createdAt: .mockISO("2026-05-25T08:00:00.000Z"),
            updatedAt: .mockISO("2026-05-25T08:00:00.000Z")
        )
    ]
}

// MARK: - Feedback Mock

extension Feedback {
    static let mockFeedbacks: [Feedback] = [
        Feedback(
            id: UUID(uuidString: "7E7BCB84-7AE6-4417-A40F-0FA13B8F1001") ?? UUID(),
            householdId: MockIDs.household,
            taskId: FamilyTask.mockTasks[0].id,
            senderId: HouseholdMembership.mockMembers[2].id,
            content: "已经接到啦，在路上回家。",
            voiceUrl: "feedbacks/mock-feedback-001.m4a",
            imageUrls: nil,
            readBy: [HouseholdMembership.mockMembers[0].id, HouseholdMembership.mockMembers[1].id],
            isDeleted: false,
            replyToId: nil,
            createdAt: .mockISO("2026-04-27T09:15:00.000Z"),
            updatedAt: nil,
            mediaClearedAt: nil
        ),
        Feedback(
            id: UUID(uuidString: "CC36F66D-B67A-4BE3-A6A3-E0E6EA4A1002") ?? UUID(),
            householdId: MockIDs.household,
            taskId: FamilyTask.mockTasks[2].id,
            senderId: nil,
            content: "执行人未在规定时间内反馈，请及时跟进。",
            voiceUrl: nil,
            imageUrls: nil,
            readBy: nil,
            isDeleted: false,
            replyToId: nil,
            createdAt: .mockISO("2026-04-27T06:30:00.000Z"),
            updatedAt: nil,
            mediaClearedAt: nil
        ),
        Feedback(
            id: UUID(uuidString: "EE1A2081-DFF2-4AE6-BB40-F1C15F111003") ?? UUID(),
            householdId: MockIDs.household,
            taskId: FamilyTask.mockTasks[1].id,
            senderId: HouseholdMembership.mockMembers[3].id,
            content: "已收到，18:20 出发去学校。",
            voiceUrl: nil,
            imageUrls: nil,
            readBy: nil,
            isDeleted: false,
            replyToId: nil,
            createdAt: .mockISO("2026-04-27T09:45:00.000Z"),
            updatedAt: .mockISO("2026-04-27T10:02:00.000Z"),
            mediaClearedAt: nil
        )
    ]
}
