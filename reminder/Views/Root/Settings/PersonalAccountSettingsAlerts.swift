import SwiftUI

extension View {
    func personalAccountSettingsAlerts(
        viewModel: MineViewModel,
        showTermsSheet: Binding<Bool>,
        showPrivacySheet: Binding<Bool>
    ) -> some View {
        alert(L10n.Common.accountDeletionFailed, isPresented: Binding(
            get: { viewModel.deleteAccountErrorMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeDeleteAccountError() } }
        )) {
            Button(L10n.Common.gotIt, role: .cancel) { viewModel.acknowledgeDeleteAccountError() }
        } message: {
            Text(verbatim: viewModel.deleteAccountErrorMessage ?? "")
        }
        .sheet(isPresented: showTermsSheet) {
            if let url = SupportLegalLinks.termsOfService {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: showPrivacySheet) {
            if let url = SupportLegalLinks.privacyPolicy {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }
}
