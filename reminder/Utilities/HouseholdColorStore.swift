import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

extension Notification.Name {
    /// 本机组织主题色变更（`object` 为 `UUID` householdId）。
    static let householdThemeColorDidChange = Notification.Name("householdThemeColorDidChange")
}

/// 本机为每个组织分配区分色（不写库）；支持预设色名或自定义 `#RRGGBB`。
enum HouseholdColorStore {
    private static let storageKey = "aifamily.householdColorAssignments"
    private static let orderKey = "aifamily.householdColorOrder"

    /// 预设语义色名。
    static let paletteNames = [
        "blue", "orange", "green", "purple", "pink", "teal", "indigo", "mint", "cyan", "brown"
    ]

    static func color(for householdId: UUID) -> Color {
        color(named: ensureAssigned(householdId))
    }

    static func colorName(for householdId: UUID) -> String {
        ensureAssigned(householdId)
    }

    static func isCustomToken(_ token: String) -> Bool {
        normalizedHex(token) != nil
    }

    static func color(named name: String) -> Color {
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
        default:
            if let custom = Color.taskCardCustomColor(fromHex: name) {
                return custom
            }
            return .blue
        }
    }

    @discardableResult
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

    /// 手动指定本机组织主题色（预设名或 `#RRGGBB`）。
    static func setColor(named name: String, for householdId: UUID) {
        let normalized: String
        if paletteNames.contains(name) {
            normalized = name
        } else if let hex = normalizedHex(name) {
            normalized = hex
        } else {
            return
        }

        var map = loadMap()
        let key = householdId.uuidString.lowercased()
        if map[key] == normalized { return }
        map[key] = normalized
        saveMap(map)
        if loadOrder().contains(key) == false {
            var order = loadOrder()
            order.append(key)
            saveOrder(order)
        }
        NotificationCenter.default.post(name: .householdThemeColorDidChange, object: householdId)
    }

    /// 从 `ColorPicker` 等写入自定义色。
    static func setCustomColor(_ color: Color, for householdId: UUID) {
        guard let hex = token(fromCustomColor: color) else { return }
        setColor(named: hex, for: householdId)
    }

    /// 将自定义 `Color` 转为可持久化的 `#RRGGBB` token（不写盘）。
    static func token(fromCustomColor color: Color) -> String? {
        hexString(from: color)
    }

    static func colorValue(fromStoredToken token: String) -> Color {
        color(named: token)
    }

    /// 规范化为 `#RRGGBB`；非法则 `nil`。
    static func normalizedHex(_ source: String) -> String? {
        var s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            s.removeFirst()
        }
        guard s.count == 3 || s.count == 6 else { return nil }
        let allowed = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        guard CharacterSet(charactersIn: s).isSubset(of: allowed) else { return nil }
        if s.count == 3 {
            s = s.map { "\($0)\($0)" }.joined()
        }
        return "#\(s.uppercased())"
    }

    private static func hexString(from color: Color) -> String? {
        #if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            // 灰度 / 其它色彩空间兜底。
            var white: CGFloat = 0
            guard uiColor.getWhite(&white, alpha: &alpha) else { return nil }
            let v = Int((white * 255).rounded())
            return String(format: "#%02X%02X%02X", v, v, v)
        }
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
        #else
        return nil
        #endif
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
    @State private var refreshToken = 0

    var body: some View {
        Circle()
            .fill(HouseholdColorStore.color(for: householdId))
            .frame(width: size, height: size)
            .id(refreshToken)
            .onReceive(NotificationCenter.default.publisher(for: .householdThemeColorDidChange)) { note in
                guard let changed = note.object as? UUID, changed == householdId else { return }
                refreshToken &+= 1
            }
    }
}
