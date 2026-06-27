import Foundation

struct ExpenseCategory: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let householdId: UUID
    let name: String
    let icon: String
    let createdAt: Date

    var displayLabel: String {
        "\(icon) \(name)"
    }

    static let defaultSeedTemplates: [(icon: String, name: String)] = [
        ("🛒", "场景采购"),
        ("🏡", "房屋物业"),
        ("🍔", "餐饮美食"),
        ("👶", "孩子养育"),
        ("🚗", "交通出行"),
        ("💊", "医疗健康"),
        ("🎁", "节日送礼"),
        ("📥", "其它杂项")
    ]
}
