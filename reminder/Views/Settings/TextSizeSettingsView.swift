import SwiftUI

struct TextSizeSettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    private var sliderUpperBound: Double {
        Double(max(AppSettingsManager.textSizeSteps.count - 1, 0))
    }

    var body: some View {
        List {
            Section {
                previewCard
            } header: {
                Text("预览")
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("较小")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(appSettings.textSizePreviewLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("最大")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(appSettings.textSizeIndex) },
                            set: { appSettings.textSizeIndex = Int($0.rounded()) }
                        ),
                        in: 0...sliderUpperBound,
                        step: 1
                    )
                    .accessibilityLabel("字体大小")
                    .accessibilityValue(appSettings.textSizePreviewLabel)
                }
                .padding(.vertical, 4)
            } footer: {
                Text("调整字体大小后，应用内文字会同步放大或缩小。")
            }
        }
        .navigationTitle("Text Size")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("周末采购清单")
                .font(.headline)

            Text("记得在周六上午检查冰箱库存，并同步更新本周的共享购物清单。")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppTheme.ColorToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.ColorToken.border, lineWidth: 1)
        )
        .dynamicTypeSize(appSettings.dynamicTypeSize)
        .animation(.easeInOut(duration: 0.2), value: appSettings.textSizeIndex)
    }
}

#Preview {
    NavigationStack {
        TextSizeSettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
