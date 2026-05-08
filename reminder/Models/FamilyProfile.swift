import Foundation

/// `family_profiles` 行：展示名与是否已绑定登录账号（`user_id`）。
struct FamilyProfile: Identifiable, Codable, Equatable {
    let id: UUID
    let householdId: UUID
    var name: String
    var userId: UUID?
}
