import SwiftUI

/// 本机为每个组织分配区分色（不写库）；按首次遇见顺序轮询调色板。
enum HouseholdColorStore {
    private static let storageKey = "aifamily.householdColorAssignments"
    private static let orderKey = "aifamily.householdColorOrder"

    /// 使用系统语义色名，避免 View 内散落 magic hex。
    private static let paletteNames = [
        "blue", "orange", "green", "purple", "pink", "teal", "indigo", "mint", "cyan", "brown"
    ]

    static func color(for householdId: UUID) -> Color {
        color(named: ensureAssigned(householdId))
    }

    static func ensureAssigned(_ householdId: UUID) -> String {
        var map = loadMap()
        if let existing = map[householdId.uuidString.lowercased()] {
            return existing
        }
        var order = loadOrder()
        let name = paletteNames[order.count % paletteNames.count]
        let key = householdId.uuidString.lowercased()
        map[key] = name
        order.append(key)
        saveMap(map)
        saveOrder(order)
        return name
    }

    static func ensureAssigned(ids: [UUID]) {
        for id in ids {
            _ = ensureAssigned(id)
        }
    }

    private static func color(named name: String) -> Color {
        switch name {
        case "blue": return .blue
        case "orange": return .orange
        case "green": return .green
        case "purple": return .purple
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "mint": return .mint
        case "cyan": return .cyan
        case "brown": return .brown
        default: return .blue
        }
    }

    private static func loadMap() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
    }

    private static func saveMap(_ map: [String: String]) {
        UserDefaults.standard.set(map, forKey: storageKey)
    }

    private static func loadOrder() -> [String] {
        UserDefaults.standard.stringArray(forKey: orderKey) ?? []
    }

    private static func saveOrder(_ order: [String]) {
        UserDefaults.standard.set(order, forKey: orderKey)
    }
}

struct HouseholdColorDot: View {
    let householdId: UUID
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(HouseholdColorStore.color(for: householdId))
            .frame(width: size, height: size)
    }
}
