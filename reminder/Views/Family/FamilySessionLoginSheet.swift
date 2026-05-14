import SwiftUI

struct FamilySessionLoginSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: AuthViewModel
    let onLoginSuccess: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("需要先登录")
                    .font(.system(size: 26, weight: .bold))
                Text("检测到当前会话无效，请先登录再加载家庭成员。")
                    .font(.system(size: 14, weight: .medium))
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
                        Text("登录并继续")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("刷新会话状态") {
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
            .navigationTitle("会话校验")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
