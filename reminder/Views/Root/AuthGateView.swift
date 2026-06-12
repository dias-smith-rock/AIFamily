import SwiftUI

struct AuthGateView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @StateObject private var viewModel = AppViewModels.makeAuthViewModel()

    var body: some View {
        Group {
            if appBootstrap.featureFlags.requireLoginForLiveMode && viewModel.isLoggedIn == false {
                loginView
            } else {
                AppTabRootView()
            }
        }
    }

    private var loginView: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalized.string(L10n.Auth.signInToWesync, locale: locale))
                    .font(.system(size: 32, weight: .bold))
                Text(AppLocalized.string(L10n.Common.supportAppleMagicLinkPhoneOtp, locale: locale))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker(AppLocalized.string(L10n.Auth.loginMethod, locale: locale), selection: $viewModel.selectedMethod) {
                    ForEach(AuthViewModel.LoginMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.selectedMethod == .magicLink {
                    TextField(AppLocalized.string(L10n.Common.emailAddress, locale: locale), text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                }

                if viewModel.selectedMethod == .phoneOTP {
                    TextField(AppLocalized.string(L10n.Common.phoneNumber, locale: locale), text: $viewModel.phone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    Task {
                        await viewModel.submit()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(AppLocalized.string(L10n.Common.continue, locale: locale))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)

                Text(viewModel.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
        }
    }
}

#Preview {
    AuthGateView()
        .environmentObject(AppBootstrap())
}
