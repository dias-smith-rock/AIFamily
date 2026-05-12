import Foundation

extension FamilyTask {
    /// 是否存在重复规则（用于完成后的 UI 分支）。
    var isRecurring: Bool {
        guard let rule = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return rule.isEmpty == false
    }
}
