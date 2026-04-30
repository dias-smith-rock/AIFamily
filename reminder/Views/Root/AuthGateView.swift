import SwiftUI

struct AuthGateView: View {
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
                Text("登录 AIFamily")
                    .font(.system(size: 32, weight: .bold))
                Text("支持 Apple、Magic Link、Phone OTP")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)

                Picker("登录方式", selection: $viewModel.selectedMethod) {
                    ForEach(AuthViewModel.LoginMethod.allCases) { method in
                        Text(method.rawValue).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.selectedMethod == .magicLink {
                    TextField("邮箱地址", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                }

                if viewModel.selectedMethod == .phoneOTP {
                    TextField("手机号", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    _Concurrency.Task {
                        await viewModel.submit()
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("继续")
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
