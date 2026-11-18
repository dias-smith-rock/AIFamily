import Foundation
@main struct PayloadTests {
    static func main() throws {
        let bytes = Data(#"{"title":"接孩子","due_date":"2026-11-19T15:00:00+08:00","end_datetime":"2026-11-19T16:00:00+08:00","is_all_day":true,"participant_hints":["爸爸"],"amount_yuan":128.5,"task_type_hint":"flexible","priority":"high"}"#.utf8)
        let task = try JSONDecoder().decode(AIParsedTaskPayload.self, from: bytes)
        assert(task.dueDate != nil && task.endDatetime != nil)
        assert(task.isAllDay && task.participantHints == ["爸爸"])
        assert(task.amountYuan == 128.5 && task.prefersFlexibleTask && task.isPriorityUrgent)
        print("Cloud payload: snake_case fields preserved")
    }
}
