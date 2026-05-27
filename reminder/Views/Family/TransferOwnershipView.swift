import SwiftUI
import Kingfisher

struct TransferOwnershipView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var familyViewModel: FamilyViewModel
    @StateObject private var viewModel: TransferOwnershipViewModel
    let onCompleted: (() -> Void)?

    init(familyViewModel: FamilyViewModel, onCompleted: (() -> Void)? = nil) {
        self.familyViewModel = familyViewModel
        self.onCompleted = onCompleted
        _viewModel = StateObject(
            wrappedValue: AppViewModels.makeTransferOwnershipViewModel(from: familyViewModel)
        )
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                hintBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                List {
                    if viewModel.eligibleMembers.isEmpty {
                        Section {
                            ContentUnavailableView {
                                Label("暂无可选成员", systemImage: "person.crop.circle.badge.questionmark")
                            } description: {
                                Text("当前没有其他可接收权限的有效账号成员。")
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section("选择接收者") {
                            ForEach(viewModel.eligibleMembers) { member in
                                Button {
                                    viewModel.selectedMember = member
                                } label: {
                                    TransferOwnershipMemberRow(member: member)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let transferError = viewModel.transferError {
                        Section {
                            Text(transferError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transfer ownership")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isTransferring)
            .confirmationDialog(
                confirmationTitle,
                isPresented: selectedMemberBinding,
                titleVisibility: .visible
            ) {
                Button("确认转移", role: .destructive) {
                    guard let member = viewModel.selectedMember else { return }
                    Task {
                        let succeeded = await viewModel.confirmTransfer(
                            to: member.userId,
                            targetDisplayName: member.nickname
                        )
                        guard succeeded else { return }
                        await familyViewModel.applyLocalRoleDowngradeAfterOwnershipTransfer()
                        familyViewModel.showTransferSuccessToast()
                        dismiss()
                        onCompleted?()
                    }
                }
                Button("取消", role: .cancel) {
                    viewModel.selectedMember = nil
                }
            } message: {
                Text("此操作不可撤销。确认后您将立即失去创建者权限。")
            }

            if viewModel.isTransferring {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text("正在转移权限…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 10)
            }
        }
    }

    private var hintBanner: some View {
        Text("转移后，您将降级为普通成员。被转移方会自动成为创建者，无需确认。请谨慎选择。")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var confirmationTitle: String {
        if let name = viewModel.selectedMember?.nickname {
            return "确定要将创建者权限转移给「\(name)」吗？"
        }
        return "确定要转移创建者权限吗？"
    }

    private var selectedMemberBinding: Binding<Bool> {
        Binding(
            get: { viewModel.selectedMember != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.selectedMember = nil
                }
            }
        )
    }
}

private struct TransferOwnershipMemberRow: View {
    let member: FamilyMember

    private var initialCharacter: String {
        String(member.nickname.prefix(1))
    }

    var body: some View {
        HStack(spacing: 14) {
            avatarView
            Text(member.nickname)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var avatarView: some View {
        if let avatarURL = member.avatarUrl.flatMap({ SupabasePublicStorageURL.resolve(storedValue: $0, bucket: SupabaseStorageBuckets.avatars) }) {
            KFImage(avatarURL)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.blue.opacity(0.14))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(initialCharacter)
                        .font(.headline)
                        .foregroundStyle(.blue)
                }
        }
    }
}

#Preview {
    NavigationStack {
        TransferOwnershipView(familyViewModel: AppViewModels.makeFamilyViewModel())
    }
}
