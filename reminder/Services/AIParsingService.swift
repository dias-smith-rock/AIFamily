import Foundation

struct TaskDraft: Equatable {
    var title: String
    var description: String?
    var dueDate: Date
    var locationName: String?
    var targetProfileIds: [UUID]?
}

protocol AIParsingService {
    func parseTaskDraft(from input: String, referenceDate: Date) async throws -> TaskDraft
}

struct RuleBasedAIParserService: AIParsingService {
    func parseTaskDraft(from input: String, referenceDate: Date) async throws -> TaskDraft {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SupabaseServiceError.invalidResponse
        }

        let normalized = trimmed.lowercased()
        let defaultHour = normalized.contains("下午") ? 15 : 9
        let calendar = Calendar.current
        let scheduled = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: referenceDate) ?? referenceDate

        return TaskDraft(
            title: extractTitle(from: trimmed),
            description: trimmed,
            dueDate: scheduled,
            locationName: normalized.contains("医院") ? "社区医院" : nil,
            targetProfileIds: nil
        )
    }

    private func extractTitle(from input: String) -> String {
        if input.count <= 18 {
            return input
        }
        let index = input.index(input.startIndex, offsetBy: 18)
        return String(input[..<index])
    }
}
