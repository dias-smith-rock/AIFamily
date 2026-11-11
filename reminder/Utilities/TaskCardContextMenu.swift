import SwiftUI

extension View {
    /// 任务 / 待办卡片长按菜单：编辑、标记完成、删除。
    @ViewBuilder
    func taskLongPressContextMenu(
        showsComplete: Bool,
        onEdit: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        contextMenu {
            Button(action: onEdit) {
                Label {
                    Text(L10n.Common.edit.localized)
                } icon: {
                    Image(systemName: "pencil")
                }
            }
            if showsComplete {
                Button(action: onComplete) {
                    Label {
                        Text(L10n.Common.markAsComplete.localized)
                    } icon: {
                        Image(systemName: "checkmark.circle")
                    }
                }
            }
            Button(role: .destructive, action: onDelete) {
                Label {
                    Text(L10n.Common.delete.localized)
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}
