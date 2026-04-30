import Foundation
import Combine

@MainActor
final class AssistantViewModel: ObservableObject {
    enum FlowState: Equatable {
        case idle
        case parsing
        case preview(TaskDraft)
        case sending
        case sent(Task)
        case failed(String)
    }

    @Published private(set) var state: FlowState = .idle
    @Published var inputText = ""

    private let taskService: TaskDataService
    private let parser: AIParsingService

    init(taskService: TaskDataService, parser: AIParsingService) {
        self.taskService = taskService
        self.parser = parser
    }

    func parseInput() async {
        state = .parsing
        do {
            let draft = try await parser.parseTaskDraft(from: inputText, referenceDate: Date())
            state = .preview(draft)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func applyNaturalLanguageCorrection(_ text: String) async {
        inputText = text
        await parseInput()
    }

    func confirmSend(assigneeId: UUID) async {
        guard case let .preview(draft) = state else { return }
        state = .sending

        let now = Date()
        let task = Task(
            id: UUID(),
            title: draft.title,
            note: draft.note,
            scheduledAt: draft.scheduledAt,
            dueAt: nil,
            location: draft.location,
            assigneeId: assigneeId,
            childName: draft.childName,
            status: .pending,
            priority: .normal,
            source: .aiAssistant,
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
