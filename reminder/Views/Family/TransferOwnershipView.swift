import SwiftUI
import Kingfisher

struct TransferOwnershipView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
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
                                Label(L10n.Family.noEligibleMembers.localized, systemImage: "person.crop.circle.badge.questionmark")
                            } description: {
                                Text(L10n.Family.thereAreNoOtherActiveAccountMembersWhoCa.localized)
                            }
                            .frame(maxWidth: .infinity, minHeight: 180)
                            .listRowBackground(Color.clear)
                        }
                    } else {
                        Section(L10n.Common.chooseRecipient) {
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
            .navigationTitle(L10n.Common.transferOwnership.localized)
            .navigationBarTitleDisplayMode(.inline)
            .disabled(viewModel.isTransferring)
            .confirmationDialog(
                confirmationTitle,
                isPresented: selectedMemberBinding,
                titleVisibility: .visible
            ) {
                Button(L10n.Common.confirmTransfer, role: .destructive) {
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
                Button(L10n.Common.cancel, role: .cancel) {
                    viewModel.selectedMember = nil
                }
            } message: {
                Text(L10n.Common.thisCannotBeUndoneYouWillImmediatelyLose.localized)
            }
            .forcesNonPopoverDialogPresentation()

            if viewModel.isTransferring {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(1.1)
                    Text(L10n.Common.transferringOwnership.localized)
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
        Text(L10n.Family.afterTransferYouWillBecomeARegularMember.localized)
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
            return L10n.Common.transferCreatorPermissionTo.formatted(locale: locale, name)
        }
        return AppLocalized.string(L10n.Common.transferCreatorPermission, locale: locale)
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
