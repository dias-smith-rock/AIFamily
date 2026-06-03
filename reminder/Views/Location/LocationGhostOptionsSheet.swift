import SwiftUI

/// 位置隐身选项：底部 sheet 列表，避免 iPad 上 `confirmationDialog` 的气泡形态。
struct LocationGhostOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let isCurrentUserGhost: Bool
    let onSelect: (GhostModeOption) -> Void

    private var selectableOptions: [GhostModeOption] {
        if isCurrentUserGhost {
            return [.pauseOneHour, .untilTonight, .keepHidden, .stopHiding]
        }
        return [.pauseOneHour, .untilTonight, .keepHidden]
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("位置共享")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 6)

            Text("选择隐藏位置的时长")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)

            Divider()

            VStack(spacing: 0) {
                ForEach(selectableOptions) { option in
                    Button {
                        onSelect(option)
                        dismiss()
                    } label: {
                        Text(option.titleKey)
                            .font(.body)
                            .foregroundStyle(option == .stopHiding ? Color.blue : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if option.id != selectableOptions.last?.id {
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }

            Divider()

            Button {
                dismiss()
            } label: {
                Text("取消")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    LocationGhostOptionsSheet(isCurrentUserGhost: true) { _ in }
}
