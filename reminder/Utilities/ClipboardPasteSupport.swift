import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 在文本输入聚焦时读取系统剪贴板，触发 iOS「是否允许粘贴」提示并填入空字段。
enum ClipboardPasteSupport {
    @MainActor
    static func pasteStringIfFieldEmpty(_ text: Binding<String>) {
        guard text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let pasted = readPasteboardString() else { return }
        text.wrappedValue = pasted
    }

    @MainActor
    static func pasteStringIfFieldEmpty(get: () -> String, set: (String) -> Void) {
        guard get().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let pasted = readPasteboardString() else { return }
        set(pasted)
    }

    @MainActor
    private static func readPasteboardString() -> String? {
        #if canImport(UIKit)
        guard let raw = UIPasteboard.general.string else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
        #else
        return nil
        #endif
    }
}

extension View {
    /// 输入框聚焦且内容为空时，尝试读取剪贴板（系统会弹出粘贴权限提示）。
    func clipboardPasteOnFocus(when isFocused: Bool, text: Binding<String>) -> some View {
        onChange(of: isFocused) { _, focused in
            guard focused else { return }
            ClipboardPasteSupport.pasteStringIfFieldEmpty(text)
        }
    }
}
