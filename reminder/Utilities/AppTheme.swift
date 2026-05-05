import SwiftUI

enum AppTheme {
    enum ColorToken {
        static let accent = Color.blue
        static let accentSoft = Color.blue.opacity(0.12)
        static let background = Color(.systemGroupedBackground)
        static let surface = Color(.systemBackground)
        static let surfaceMuted = Color(.secondarySystemGroupedBackground)
        static let border = Color.gray.opacity(0.14)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let danger = Color.red
    }

    enum FontToken {
        static let hero = Font.system(size: 38, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let section = Font.system(size: 22, weight: .bold, design: .rounded)
        static let subtitle = Font.system(size: 16, weight: .medium)
        static let body = Font.system(size: 16, weight: .regular)
        static let bodyStrong = Font.system(size: 16, weight: .semibold)
        static let caption = Font.system(size: 13, weight: .medium)
    }
}

struct AppCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(AppTheme.ColorToken.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(AppTheme.ColorToken.border, lineWidth: 1)
            )
    }
}

extension View {
    func appCard() -> some View {
        modifier(AppCardModifier())
    }
}
