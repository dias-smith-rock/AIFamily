import Foundation

enum LedgerAccessControl {
    static func canAccessFamilyExpense(role: MembershipRole) -> Bool {
        role == .creator || role == .admin
    }
}
