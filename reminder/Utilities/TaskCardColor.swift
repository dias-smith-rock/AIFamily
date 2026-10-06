import SwiftUI

// MARK: - Hex ↔ SwiftUI（任务卡片 `background_color`）

extension Color {
    /// 任务卡片暗色表面（仅深色外观使用）。
    static var taskCardDarkSurface: Color {
        Color(red: 22 / 255, green: 30 / 255, blue: 46 / 255)
    }

    /// 浅色外观用系统卡片白底，避免海军黑块压在浅灰页面上。
    static func taskCardSurface(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return .taskCardDarkSurface
        default:
            return Color(.systemBackground)
        }
    }

    static func taskCardTitle(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : .primary
    }

    static func taskCardSecondary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.55) : .secondary
    }

    static func taskCardTertiary(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.45) : Color(.tertiaryLabel)
    }

    static func taskCardChipFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.primary.opacity(0.06)
    }

    static func taskCardStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }

    static func taskCardAvatarPlaceholder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.22) : Color(.secondarySystemFill)
    }

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
    /// 卡片铺底：固定暗色表面（不同家庭靠强调色区分）。
    /// 卡片铺底：浅色用系统白底，深色用海军表面。
    func cardBackgroundColor(for colorScheme: ColorScheme) -> Color {
        Color.taskCardSurface(for: colorScheme)
    }

    /// 组织主题强调色：左侧条 / 图标 / 头像描边（每家庭不同）。
    var cardThemeAccentColor: Color {
        HouseholdColorStore.color(for: householdId)
    }

    /// 左侧强调条：任务自定义色优先，否则组织主题色。
    var cardHeaderAccentColor: Color {
        Color.taskCardCustomColor(fromHex: backgroundColor) ?? cardThemeAccentColor
    }
}

/// 在卡片内容上叠加暗色底 + 左侧主题色条（贴齐左边缘，由卡片圆角裁切）。
struct TaskCardSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let headerAccentColor: Color
    var cornerRadius: CGFloat = 12
    var headerBarWidth: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .background(Color.taskCardSurface(for: colorScheme))
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(headerAccentColor)
                    .frame(width: headerBarWidth)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func taskCardSurface(
        for task: FamilyTask,
        cornerRadius: CGFloat = 12,
        headerBarWidth: CGFloat = 4
    ) -> some View {
        modifier(
            TaskCardSurfaceModifier(
                headerAccentColor: task.cardHeaderAccentColor,
                cornerRadius: cornerRadius,
                headerBarWidth: headerBarWidth
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
