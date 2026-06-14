import SwiftUI

/// 游客退出：软退出 / 绑定账号 / 硬退出（清除会话）。
struct GuestSessionExitDialogs: ViewModifier {
    @EnvironmentObject private var appRouter: AppRouter
    @Binding var showGuestExitDialog: Bool
    @Binding var showLinkAccountSheet: Bool
    @Binding var isProcessing: Bool
    var onError: (String) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                L10n.Auth.guestExitOptionsTitle.localized,
                isPresented: $showGuestExitDialog,
                titleVisibility: .visible
            ) {
                Button(L10n.Auth.guestReturnToLoginKeepData) {
                    SupabaseAuthManager.softExitToLogin(appRouter: appRouter)
                }
                Button(L10n.Auth.guestBindAccount) {
                    showLinkAccountSheet = true
                }
                Button(L10n.Auth.guestStartFreshExperience, role: .destructive) {
                    Task { await performHardSignOut() }
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            } message: {
                Text(L10n.Auth.guestExitOptionsMessage.localized)
            }
            .forcesNonPopoverDialogPresentation()
            .sheet(isPresented: $showLinkAccountSheet) {
                NavigationStack {
                    AnonymousAccountLinkCard {
                        showLinkAccountSheet = false
                        Task { await appRouter.refreshStateFromBackend() }
                    }
                    .padding()
                    .navigationTitle(L10n.Auth.guestBindAccount.localized)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(L10n.Common.close) {
                                showLinkAccountSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
    }

    private func performHardSignOut() async {
        guard isProcessing == false else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            try await SupabaseAuthManager.hardSignOut(appRouter: appRouter, clearGuestArchive: true)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

extension View {
    func guestSessionExitDialogs(
        showGuestExitDialog: Binding<Bool>,
        showLinkAccountSheet: Binding<Bool>,
        isProcessing: Binding<Bool>,
        onError: @escaping (String) -> Void
    ) -> some View {
        modifier(
            GuestSessionExitDialogs(
                showGuestExitDialog: showGuestExitDialog,
                showLinkAccountSheet: showLinkAccountSheet,
                isProcessing: isProcessing,
                onError: onError
            )
        )
    }
}
