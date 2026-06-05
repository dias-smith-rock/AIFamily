import Foundation
import Combine

@MainActor
final class AssistantViewModel: ObservableObject {
    enum FlowState: Equatable {
        case idle
        case parsing
        case preview(TaskDraft)
        case sending
        case sent(FamilyTask)
        case failed(String)
    }

    @Published private(set) var state: FlowState = .idle
    @Published var inputText = ""

    private let taskService: TaskDataService
    private let parser: AIParsingService
    /// 与日程选中日对齐，用于 `parseTaskDraft` 的 `referenceDate`（含「明天」等相对语义）。
    private var referenceCalendarDay: Date = Calendar.current.startOfDay(for: Date())

    init(taskService: TaskDataService, parser: AIParsingService) {
        self.taskService = taskService
        self.parser = parser
    }

    func setReferenceCalendarDay(_ date: Date) {
        referenceCalendarDay = Calendar.current.startOfDay(for: date)
    }

    func parseInput() async {
        state = .parsing
        do {
            let draft = try await parser.parseTaskDraft(from: inputText, referenceDate: referenceCalendarDay)
            state = .preview(draft)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func applyNaturalLanguageCorrection(_ text: String) async {
        inputText = text
        await parseInput()
    }

    /// 把预检卡片提交到后端。
    /// - Parameters:
    ///   - householdId: 当前群组 ID（由上层路由层注入，避免 VM 自己跨层取数据）。
    ///   - creatorMembershipId: 创建者在 `household_memberships` 中的主键。
    ///   - involvedMemberIds: 涉及到的成员（执行人 / 跟进人）。
    func confirmSend(
        householdId: UUID,
        creatorMembershipId: UUID,
        involvedMemberIds: [UUID]?
    ) async {
        guard case let .preview(draft) = state else { return }
        state = .sending

        let now = Date()
        let task = FamilyTask(
            id: UUID(),
            householdId: householdId,
            creatorId: creatorMembershipId,
            parentTaskId: nil,
            originalDueDate: draft.dueDate,
            involvedMemberIds: involvedMemberIds,
            targetProfileIds: draft.targetProfileIds,
            targetSubject: nil,
            title: draft.title,
            description: draft.description,
            originalPrompt: inputText,
            attachmentUrls: nil,
            externalContacts: nil,
            locationData: draft.locationName.map { FamilyTask.LocationData(name: $0, address: nil, latitude: nil, longitude: nil) },
            externalSyncRefs: nil,
            alarmSetBy: nil,
            status: .new,
            priority: .normal,
            taskType: TaskTypeKind.scheduled.rawValue,
            dueDate: draft.dueDate,
            isAllDay: false,
            recurrenceRule: nil,
            reminderOffsets: nil,
            estimatedCost: 0,
            createdAt: now,
            updatedAt: now
        )

        do {
            let created = try await taskService.createTask(task)
            state = .sent(created)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func reset() {
        state = .idle
        inputText = ""
    }
}
