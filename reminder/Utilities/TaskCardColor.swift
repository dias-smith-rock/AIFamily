import SwiftUI

// MARK: - Hex ↔ SwiftUI（任务卡片 `background_color`）

extension Color {
    /// 列表卡片左侧强调条：`nil`/非法十六进制时返回 **系统强调色**（与 `taskCardListBackground` 的「卡片底色」语义不同）。
    static func taskCardLeadingAccent(fromHex hex: String?) -> Color {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return Color.accentColor
        }
        guard let rgb = RGBComponents.parseHexString(raw) else {
            return Color.accentColor
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// 列表卡片：无自定义色或解析失败时使用系统二级分组背景。
    static func taskCardListBackground(fromHex hex: String?) -> Color {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false else {
            return Color(.secondarySystemGroupedBackground)
        }
        guard let rgb = RGBComponents.parseHexString(raw) else {
            return Color(.secondarySystemGroupedBackground)
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// 写入数据库：与「默认白卡片」等价的浅色不写入（`nil`）；否则返回 `#RRGGBB` 大写。
    func taskCardHexForStorage(in environment: EnvironmentValues) -> String? {
        let resolved = resolve(in: environment)
        let r = Double(resolved.red)
        let g = Double(resolved.green)
        let b = Double(resolved.blue)
        if r >= 0.97, g >= 0.97, b >= 0.97 {
            return nil
        }
        let ri = Int((r * 255).rounded(.toNearestOrAwayFromZero))
        let gi = Int((g * 255).rounded(.toNearestOrAwayFromZero))
        let bi = Int((b * 255).rounded(.toNearestOrAwayFromZero))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }

    /// 从已存十六进制初始化取色器状态；无效或空则回退为白（与默认卡片一致）。
    static func taskCardPickerTint(fromStoredHex hex: String?) -> Color {
        guard let raw = hex?.trimmingCharacters(in: .whitespacesAndNewlines), raw.isEmpty == false,
              let rgb = RGBComponents.parseHexString(raw) else {
            return .white
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

// MARK: - RGB 解析（无 UIKit）

private struct RGBComponents {
    let red: Double
    let green: Double
    let blue: Double

    static func parseHexString(_ source: String) -> RGBComponents? {
        var s = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") {
            s.removeFirst()
        }
        guard s.count == 3 || s.count == 6 else { return nil }
        guard CharacterSet(charactersIn: s).isSubset(of: CharacterSet.hexadecimalCharacters) else {
            return nil
        }

        if s.count == 3 {
            let chars = Array(s)
            let expanded = chars.map { String([$0, $0]) }.joined()
            s = expanded
        }

        guard let value = UInt32(s, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return RGBComponents(red: r, green: g, blue: b)
    }
}

private extension CharacterSet {
    static let hexadecimalCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: L10n.Common.n0 ... "9")
        set.insert(charactersIn: "a" ... "f")
        set.insert(charactersIn: "A" ... "F")
        return set
    }()
}
