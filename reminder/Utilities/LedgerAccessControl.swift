import Foundation

enum LedgerAccessControl {
    /// 完整公账（支出+收入网格、报表、分类管理）：仅 creator / admin。
    static func canAccessFamilyExpense(role: MembershipRole) -> Bool {
        role == .creator || role == .admin
    }

    /// 记收入（进账）：所有活跃成员（含 member /「游客」）。
    static func canRecordIncome(role: MembershipRole) -> Bool {
        switch role {
        case .creator, .admin, .member:
            true
        }
    }
}
