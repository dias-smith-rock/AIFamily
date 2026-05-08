import SwiftUI

/// 各 Tab 顶部统一头部：背景延伸至刘海区域，底部留有分隔与轻微层次，与日程表 Tab 视觉一致。
struct GlobalHeaderView<Leading: View, Trailing: View>: View {
    private let leading: Leading
    private let trailing: Trailing

    init(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.leading = leading()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            leading
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            headerChrome
        }
    }

    private var headerChrome: some View {
        ZStack(alignment: .bottom) {
            AppTheme.ColorToken.background
                .ignoresSafeArea(.container, edges: .top)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(AppTheme.ColorToken.border.opacity(0.55))
                    .frame(height: 1)

                LinearGradient(
                    colors: [
                        Color.black.opacity(0.06),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 10)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

extension GlobalHeaderView where Trailing == EmptyView {
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading, trailing: { EmptyView() })
    }
}
