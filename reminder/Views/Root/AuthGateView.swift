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
                Text(AppLocalized.string("登录同圈", locale: locale))
                    .font(.system(size: 32, weight: .bold))
                Text(AppLocalized.string("支持 Apple、Magic Link、Phone OTP", locale: locale))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker(AppLocalized.string("登录方式", locale: locale), selection: $viewModel.selectedMethod) {
                    ForEach(AuthViewModel.LoginMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.selectedMethod == .magicLink {
                    TextField(AppLocalized.string("邮箱地址", locale: locale), text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                }

                if viewModel.selectedMethod == .phoneOTP {
                    TextField(AppLocalized.string("手机号", locale: locale), text: $viewModel.phone)
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
                        Text(AppLocalized.string("继续", locale: locale))
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
