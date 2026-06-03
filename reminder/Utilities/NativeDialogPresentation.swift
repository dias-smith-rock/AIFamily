import SwiftUI

extension View {
    /// 在 iPad 上强制 `confirmationDialog` 以底部 sheet 呈现，避免系统 popover 气泡形态。
    func forcesNonPopoverDialogPresentation() -> some View {
        presentationCompactAdaptation(.sheet)
    }
}
