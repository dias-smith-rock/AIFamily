import SwiftUI

extension Text {
    init(_ entry: L10n.Entry) {
        self.init(entry.localized)
    }
}

extension Button where Label == Text {
    init(_ entry: L10n.Entry, action: @escaping () -> Void) {
        self.init(entry.localized, action: action)
    }

    init(_ entry: L10n.Entry, role: ButtonRole?, action: @escaping () -> Void) {
        self.init(entry.localized, role: role, action: action)
    }
}

extension View {
    func alert(
        _ entry: L10n.Entry,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> some View,
        @ViewBuilder message: () -> some View = { EmptyView() }
    ) -> some View {
        alert(entry.localized, isPresented: isPresented, actions: actions, message: message)
    }

    func accessibilityLabel(_ entry: L10n.Entry) -> some View {
        accessibilityLabel(entry.localized)
    }

    func navigationTitle(_ entry: L10n.Entry) -> some View {
        navigationTitle(entry.localized)
    }

    func confirmationDialog(
        _ entry: L10n.Entry,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        confirmationDialog(entry.localized, isPresented: isPresented, titleVisibility: titleVisibility, actions: actions)
    }
}

extension Section where Parent == Text, Content: View, Footer == EmptyView {
    init(_ entry: L10n.Entry, @ViewBuilder content: () -> Content) {
        self.init(entry.localized, content: content)
    }
}
