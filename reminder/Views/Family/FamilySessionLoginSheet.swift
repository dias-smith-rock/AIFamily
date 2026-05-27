import SwiftUI

struct FamilySessionLoginSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel
    let onLoginSuccess: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text(AppLocalized.string("需要先登录", locale: locale))
                    .font(.system(size: 26, weight: .bold))
                Text(AppLocalized.string("检测到当前会话无效，请先登录再加载群组成员。", locale: locale))
                    .font(.system(size: 14, weight: .medium))
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
                        if viewModel.isLoggedIn {
                            await onLoginSuccess()
                            dismiss()
                        }
                    }
                } label: {
                    if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text(AppLocalized.string("登录并继续", locale: locale))
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button(AppLocalized.string("刷新会话状态", locale: locale)) {
                    Task {
                        await viewModel.refreshSessionState()
                        if viewModel.isLoggedIn {
                            await onLoginSuccess()
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.bordered)

                Text(viewModel.statusText)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppLocalized.string("会话校验", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
