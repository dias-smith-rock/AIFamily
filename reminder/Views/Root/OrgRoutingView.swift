import SwiftUI
import UIKit

struct OrgRoutingView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var householdName = ""
    @State private var inviteCode = ""
    @State private var detectedInviteCode = ""
    @State private var showClipboardPrompt = false
    @State private var showErrorAlert = false
    @FocusState private var focusedField: InputField?

    private enum InputField: Hashable {
        case householdName
        case inviteCode
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                createSection
                joinSection
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    focusedField = nil
                }
            }
        }
        .onAppear {
            sniffClipboard()
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showErrorAlert = newValue != nil
        }
        .alert("检测到邀请码", isPresented: $showClipboardPrompt) {
            Button("直接加入") {
                submitJoin()
            }
            Button("稍后再说", role: .cancel) {}
        } message: {
            Text("检测到邀请码 \(detectedInviteCode)，是否直接加入？")
        }
        .alert("操作失败", isPresented: $showErrorAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "请稍后重试")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选择组织方式")
                .font(.system(size: 30, weight: .bold))
            Text("创建新家庭，或通过邀请码加入家人组织。")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private var createSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("创建新家庭")
                .font(.system(size: 18, weight: .semibold))

            TextField("请输入家庭名称（如：小明一家）", text: $householdName)
                .autocorrectionDisabled(true)
                .focused($focusedField, equals: .householdName)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            Button {
                submitCreate()
            } label: {
                rowButtonLabel(
                    title: "我是家庭管理员，立即创建",
                    loading: viewModel.isCreating
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCreating || viewModel.isJoining || normalizedHouseholdName.isEmpty)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var joinSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("扫码 / 输入邀请码加入")
                .font(.system(size: 18, weight: .semibold))

            TextField("请输入 6 位邀请码", text: $inviteCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .focused($focusedField, equals: .inviteCode)
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            if normalizedInviteCode.isEmpty == false && isInviteCodeValid == false {
                Text("邀请码格式错误：需为 6 位字母或数字")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                submitJoin()
            } label: {
                rowButtonLabel(
                    title: "提交邀请码并申请加入",
                    loading: viewModel.isJoining
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCreating || viewModel.isJoining || isInviteCodeValid == false)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func rowButtonLabel(title: String, loading: Bool) -> some View {
        HStack(spacing: 8) {
            if loading {
                ProgressView()
            }
            Text(title)
                .font(.system(size: 16, weight: .semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.blue)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var normalizedInviteCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var normalizedHouseholdName: String {
        householdName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isInviteCodeValid: Bool {
        normalizedInviteCode.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil
    }

    private func sniffClipboard() {
        guard let text = UIPasteboard.general.string?.uppercased() else { return }
        if let code = firstInviteCode(from: text) {
            inviteCode = code
            detectedInviteCode = code
            showClipboardPrompt = true
        }
    }

    private func firstInviteCode(from text: String) -> String? {
        let pattern = "\\b[A-Z0-9]{6}\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    private func submitCreate() {
        _Concurrency.Task {
            let success = await viewModel.createHousehold(displayName: normalizedHouseholdName)
            guard success else { return }
            await appRouter.refreshStateFromBackend()
        }
    }

    private func submitJoin() {
        focusedField = nil
        guard isInviteCodeValid else {
            return
        }
        _Concurrency.Task {
            let success = await viewModel.joinHousehold(inviteCode: normalizedInviteCode)
            guard success else { return }
            await appRouter.refreshStateFromBackend()
        }
    }
}

#Preview {
    OrgRoutingView()
        .environmentObject(AppRouter())
}
