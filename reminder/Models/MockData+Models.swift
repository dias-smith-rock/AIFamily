import Foundation

extension Date {
    static func mockISO(_ value: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? Date()
    }
}

extension FamilyMember {
    static let mockMembers: [FamilyMember] = [
        FamilyMember(
            id: UUID(uuidString: "8AC693C1-B0EE-4E44-A87A-EFC3A3A1A001") ?? UUID(),
            displayName: "爸爸",
            role: .father,
            permission: .owner,
            notificationChannel: .app,
            phoneNumber: "13800138000",
            avatarEmoji: "👨",
            notificationsEnabled: true,
            inviteToken: "invite-father-demo",
            bindingStatus: .linked,
            createdAt: .mockISO("2026-04-01T08:00:00.000Z"),
            updatedAt: .mockISO("2026-04-27T08:30:00.000Z")
        ),
        FamilyMember(
            id: UUID(uuidString: "1E4F2CE0-7F66-4B2D-8A0A-3C880D5A4002") ?? UUID(),
            displayName: "妈妈",
            role: .mother,
            permission: .manager,
            notificationChannel: .app,
            phoneNumber: "13900139000",
            avatarEmoji: "👩",
            notificationsEnabled: true,
            inviteToken: "invite-mother-demo",
            bindingStatus: .linked,
            createdAt: .mockISO("2026-04-01T08:00:00.000Z"),
            updatedAt: .mockISO("2026-04-27T08:32:00.000Z")
        ),
        FamilyMember(
            id: UUID(uuidString: "D9D43B14-CB56-4E4B-ABF7-6FAAA41F2003") ?? UUID(),
            displayName: "奶奶",
            role: .grandparent,
            permission: .executor,
            notificationChannel: .wechat,
            phoneNumber: "13700137000",
            avatarEmoji: "👵",
            notificationsEnabled: true,
            inviteToken: "invite-grandma-demo",
            bindingStatus: .linked,
            createdAt: .mockISO("2026-04-05T09:20:00.000Z"),
            updatedAt: .mockISO("2026-04-27T07:45:00.000Z")
        ),
        FamilyMember(
            id: UUID(uuidString: "7D8B4FA4-EE8B-41E4-BB4A-2C67BB9E3004") ?? UUID(),
            displayName: "保姆",
            role: .caregiver,
            permission: .executor,
            notificationChannel: .wechat,
            phoneNumber: "13600136000",
            avatarEmoji: "🧑",
            notificationsEnabled: false,
            inviteToken: "invite-caregiver-demo",
            bindingStatus: .pending,
            createdAt: .mockISO("2026-04-10T03:10:00.000Z"),
            updatedAt: .mockISO("2026-04-27T07:50:00.000Z")
        )
    ]
}

extension Task {
    static let mockTasks: [Task] = [
        Task(
            id: UUID(uuidString: "A4795A12-72C1-49B6-88A2-2A6B47A51001") ?? UUID(),
            title: "接补习班",
            note: "下课后先确认作业本是否带齐。",
            scheduledAt: .mockISO("2026-04-27T09:00:00.000Z"),
            dueAt: .mockISO("2026-04-27T09:30:00.000Z"),
            location: "艺术中心",
            assigneeId: FamilyMember.mockMembers[2].id,
            childName: "小明",
            status: .completed,
            priority: .high,
            source: .aiAssistant,
            createdAt: .mockISO("2026-04-27T02:00:00.000Z"),
            updatedAt: .mockISO("2026-04-27T09:20:00.000Z")
        ),
        Task(
            id: UUID(uuidString: "B55B6EA1-A357-46D2-B7E9-8B359E6D1002") ?? UUID(),
            title: "接放学",
            note: "17:20 前到校门口，避免晚高峰拥堵。",
            scheduledAt: .mockISO("2026-04-27T10:30:00.000Z"),
            dueAt: .mockISO("2026-04-27T11:00:00.000Z"),
            location: "学校门口",
            assigneeId: FamilyMember.mockMembers[3].id,
            childName: "小明",
            status: .pending,
            priority: .urgent,
            source: .manual,
            createdAt: .mockISO("2026-04-27T03:20:00.000Z"),
            updatedAt: .mockISO("2026-04-27T03:20:00.000Z")
        ),
        Task(
            id: UUID(uuidString: "C82D9000-6AD8-4A68-9F84-4AE465BA1003") ?? UUID(),
            title: "体检复查",
            note: "带医保卡、上次检查报告。",
            scheduledAt: .mockISO("2026-04-27T06:00:00.000Z"),
            dueAt: .mockISO("2026-04-27T06:20:00.000Z"),
            location: "社区医院",
            assigneeId: FamilyMember.mockMembers[0].id,
            childName: "小明",
            status: .overdue,
            priority: .high,
            source: .importedMessage,
            createdAt: .mockISO("2026-04-26T14:10:00.000Z"),
            updatedAt: .mockISO("2026-04-27T06:30:00.000Z")
        )
    ]
}

extension Feedback {
    static let mockFeedbacks: [Feedback] = [
        Feedback(
            id: UUID(uuidString: "7E7BCB84-7AE6-4417-A40F-0FA13B8F1001") ?? UUID(),
            taskId: Task.mockTasks[0].id,
            senderId: FamilyMember.mockMembers[2].id,
            type: .voice,
            text: "已经接到啦，在路上回家。",
            audioURL: URL(string: "https://example.com/audio/feedback-001.m4a"),
            audioDurationSeconds: 3,
            isRead: true,
            createdAt: .mockISO("2026-04-27T09:15:00.000Z")
        ),
        Feedback(
            id: UUID(uuidString: "CC36F66D-B67A-4BE3-A6A3-E0E6EA4A1002") ?? UUID(),
            taskId: Task.mockTasks[2].id,
            senderId: FamilyMember.mockMembers[0].id,
            type: .system,
            text: "执行人未在规定时间内反馈，请及时跟进。",
            audioURL: nil,
            audioDurationSeconds: nil,
            isRead: false,
            createdAt: .mockISO("2026-04-27T06:30:00.000Z")
        ),
        Feedback(
            id: UUID(uuidString: "EE1A2081-DFF2-4AE6-BB40-F1C15F111003") ?? UUID(),
            taskId: Task.mockTasks[1].id,
            senderId: FamilyMember.mockMembers[3].id,
            type: .text,
            text: "已收到，18:20 出发去学校。",
            audioURL: nil,
            audioDurationSeconds: nil,
            isRead: false,
            createdAt: .mockISO("2026-04-27T09:45:00.000Z")
        )
    ]
}
