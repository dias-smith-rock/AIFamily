import SwiftUI

// MARK: - Hex ↔ SwiftUI（任务卡片 `background_color`）

extension Color {
    /// 列表卡片左侧强调条：`nil`/非法十六进制时返回 **系统强调色**（与 `taskCardListBackground` 的「卡片底色」语义不同）。
    static func taskCardLeadingAccent(fromHex hex: String?) -> Color {
        guard let rgb = RGBComponents.parseOptionalHex(hex) else {
            return Color.accentColor
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// 列表卡片：无自定义色或解析失败时使用系统二级分组背景。
    static func taskCardListBackground(fromHex hex: String?) -> Color {
        guard let rgb = RGBComponents.parseOptionalHex(hex) else {
            return Color(.secondarySystemGroupedBackground)
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    /// 解析任务自定义色；无效或未设置时返回 `nil`。
    static func taskCardCustomColor(fromHex hex: String?) -> Color? {
        guard let rgb = RGBComponents.parseOptionalHex(hex) else { return nil }
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
        guard let rgb = RGBComponents.parseOptionalHex(hex) else {
            return .white
        }
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

extension FamilyTask {
    /// 卡片铺底色：始终使用组织色。
    var cardBackgroundColor: Color {
        HouseholdColorStore.color(for: householdId)
    }

    /// 左侧「卡片头」色条：仅创建/编辑时选定了颜色才返回。
    var cardHeaderAccentColor: Color? {
        Color.taskCardCustomColor(fromHex: backgroundColor)
    }
}

/// 在卡片内容上叠加组织色底 + 左侧任务色头条。
struct TaskCardSurfaceModifier: ViewModifier {
    let backgroundColor: Color
    let headerAccentColor: Color?
    var cornerRadius: CGFloat = 12
    var headerBarWidth: CGFloat = 4
    var headerVerticalInset: CGFloat = 8
    var headerLeadingInset: CGFloat = 5

    func body(content: Content) -> some View {
        content
            .background(backgroundColor)
            .overlay(alignment: .leading) {
                if let headerAccentColor {
                    Capsule()
                        .fill(headerAccentColor)
                        .frame(width: headerBarWidth)
                        .padding(.vertical, headerVerticalInset)
                        .padding(.leading, headerLeadingInset)
                        .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func taskCardSurface(
        for task: FamilyTask,
        cornerRadius: CGFloat = 12,
        headerBarWidth: CGFloat = 4,
        headerVerticalInset: CGFloat = 8,
        headerLeadingInset: CGFloat = 5
    ) -> some View {
        modifier(
            TaskCardSurfaceModifier(
                backgroundColor: task.cardBackgroundColor,
                headerAccentColor: task.cardHeaderAccentColor,
                cornerRadius: cornerRadius,
                headerBarWidth: headerBarWidth,
                headerVerticalInset: headerVerticalInset,
                headerLeadingInset: headerLeadingInset
            )
        )
    }
}

// MARK: - RGB 解析（无 UIKit）

private struct RGBComponents {
    let red: Double
    let green: Double
    let blue: Double

    static func parseOptionalHex(_ source: String?) -> RGBComponents? {
        guard let raw = source?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }
        return parseHexString(raw)
    }

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
        set.insert(charactersIn: "0" ... "9")
        set.insert(charactersIn: "a" ... "f")
        set.insert(charactersIn: "A" ... "F")
        return set
    }()
}
