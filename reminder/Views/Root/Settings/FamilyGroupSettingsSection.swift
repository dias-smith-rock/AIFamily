import SwiftUI

enum FamilyAddMemberRoute: Identifiable, Equatable {
    case entry
    case invite

    var id: String {
        switch self {
        case .entry: return "entry"
        case .invite: return "invite"
        }
    }
}

struct FamilyGroupSettingsSection: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator

    @ObservedObject var viewModel: FamilyViewModel
    @Binding var addMemberRoute: FamilyAddMemberRoute?
    @Binding var editingProfile: FamilyProfile?
    @Binding var selectedProfileForDetail: FamilyProfile?
    @Binding var isSortingMembers: Bool
    @Binding var isShowingRenameHouseholdSheet: Bool
    var onOpenOrganizationSettings: () -> Void

    var body: some View {
        familyListContent
    }

    // MARK: - List Content

    @ViewBuilder
    private var familyListContent: some View {
        if viewModel.isLoading && viewModel.hasLoadedOnce == false {
            ProgressView(AppLocalized.string(L10n.Family.loadingMemberProfiles, locale: locale))
                .frame(maxWidth: .infinity, minHeight: 220)
                .listRowBackground(Color.clear)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label(AppLocalized.string(L10n.Common.loading, locale: locale), systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(AppLocalized.string(L10n.Common.reload, locale: locale)) {
                    Task {
                        await viewModel.loadMembers()
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .listRowBackground(Color.clear)
        } else if viewModel.orderedProfiles.isEmpty {
            Section {
                householdSummaryRow
                profilesEmptyState
            }
            .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        } else {
            Section {
                householdSummaryRow
                    .listRowInsets(
                        EdgeInsets(
                            top: 2,
                            leading: 16,
                            bottom: creatorProfile != nil ? 2 : 8,
                            trailing: 16
                        )
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(creatorProfile == nil ? .automatic : .hidden, edges: .bottom)

                if let creator = creatorProfile {
                    FamilyMemberRowView(
                        profile: creator,
                        isVirtualUser: creator.isVirtualUser,
                        isCurrentUser: isCurrentUserProfile(creator),
                        prominentRole: prominentListRole(for: creator)
                    ) {
                        presentMemberFlow(for: creator)
                    }
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden, edges: .top)
                }
            }

            Section {
                if membersExcludingCreator.isEmpty {
                    otherMembersEmptyState
                } else {
                    ForEach(membersExcludingCreator) { profile in
                        FamilyMemberRowView(
                            profile: profile,
                            isVirtualUser: profile.isVirtualUser,
                            isCurrentUser: isCurrentUserProfile(profile),
                            prominentRole: prominentListRole(for: profile)
                        ) {
                            presentMemberFlow(for: profile)
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                    }
                    .onMove { indexSet, destination in
                        guard isSortingMembers else { return }
                        viewModel.moveNonCreatorProfiles(fromOffsets: indexSet, toOffset: destination)
                    }
                }
            } header: {
                otherMembersSectionHeader
            }
        }
    }

    private var otherMembersEmptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text(L10n.Family.noOtherMembersYet.localized)
                .foregroundStyle(.secondary)

            Button(L10n.Family.addGroupMembers) {
                presentAddMemberFlow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func presentAddMemberFlow() {
        Task { @MainActor in
            guard viewModel.canAddMember(hasPremiumAccess: appRouter.hasPremiumAccess) else {
                appRouter.presentPremiumUpgrade()
                return
            }
            addMemberRoute = .entry
        }
    }

    private var profilesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(AppTheme.ColorToken.accent.opacity(0.85))
                .symbolRenderingMode(.hierarchical)
            Text(L10n.Family.noMemberProfileYet.localized)
                .font(.headline)
            Text(L10n.Schedule.addTheFirstMemberToShareTasksAndGentleD.localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button(L10n.Family.addGroupMembers) {
                presentAddMemberFlow()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// 组织名称 + 图标：标题区切换组织，副标题进入组织设置。
    private var householdSummaryRow: some View {
        householdSummaryRowContent
            .accessibilityElement(children: .contain)
    }

    private var householdSummaryRowContent: some View {
        HStack(alignment: .center, spacing: 0) {
            Button {
                onOpenOrganizationSettings()
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.orange.opacity(0.2))
                        .frame(width: 50, height: 50)
                        .overlay {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.orange)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(currentOrganizationDisplayName)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if canManageHousehold {
                                Image(systemName: "square.and.pencil")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        organizationDescriptionSubtitle
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(canManageHousehold == false || appRouter.selectedHouseholdId == nil)

            Button {
                groupSwitcher.present(mode: .singleActive)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Family.switchGroup)
        }
        .padding(.vertical, 6)
    }

    private var currentOrganizationDisplayName: String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return L10n.Family.unnamedGroup.string() }
        return StoredDisplayNameResolver.householdName(trimmed)
    }

    @ViewBuilder
    private var organizationDescriptionSubtitle: some View {
        let trimmed = appRouter.selectedHouseholdDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            Text(trimmed)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private var otherMembersSectionHeader: some View {
        HStack(spacing: 16) {
            Text(L10n.Family.groupMembers.localized)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if membersExcludingCreator.count >= 2 {
                Button {
                    withAnimation(.snappy) {
                        isSortingMembers.toggle()
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.body)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    isSortingMembers
                        ? AppLocalized.string(L10n.Common.completeSorting, locale: locale)
                        : AppLocalized.string(L10n.Family.sortGroupMembers, locale: locale)
                )
            }

            if membersExcludingCreator.isEmpty == false {
                Button {
                    presentAddMemberFlow()
                } label: {
                    Image(systemName: "plus")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalized.string(L10n.Family.addGroupMembers, locale: locale))
            }
        }
        .textCase(nil)
    }

    private var creatorProfile: FamilyProfile? {
        viewModel.orderedProfiles.first(where: { isCreatorProfile($0) })
    }

    private var membersExcludingCreator: [FamilyProfile] {
        viewModel.orderedProfiles.filter { isCreatorProfile($0) == false }
    }

    /// 有编辑权限时直接进入编辑页，否则进入只读详情。
    private func presentMemberFlow(for profile: FamilyProfile) {
        if viewModel.canEditProfile(profile) {
            editingProfile = profile
        } else {
            selectedProfileForDetail = profile
        }
    }

    private func isCurrentUserProfile(_ profile: FamilyProfile) -> Bool {
        guard let selectedMembershipId = appRouter.selectedMembershipId,
              let currentMembership = viewModel.members.first(where: { $0.id == selectedMembershipId }) else {
            return false
        }
        if currentMembership.profileId == profile.id {
            return true
        }
        return resolvedMembership(for: profile)?.id == selectedMembershipId
    }

    private func isCreatorProfile(_ profile: FamilyProfile) -> Bool {
        if profile.currentRole == MembershipRole.creator.rawValue { return true }
        return resolvedMembership(for: profile)?.hasRole(.creator) == true
    }

    private func resolvedMembership(for profile: FamilyProfile) -> HouseholdMembership? {
        profile.primaryMembership ?? viewModel.membership(for: profile)
    }

    /// 行内显著角色：创建者优先于管理员；普通成员不展示胶囊。
    private func prominentListRole(for profile: FamilyProfile) -> MembershipRole? {
        if profile.currentRole == MembershipRole.creator.rawValue { return .creator }
        if profile.currentRole == MembershipRole.admin.rawValue { return .admin }
        if let role = resolvedMembership(for: profile)?.parsedRole {
            switch role {
            case .creator, .admin:
                return role
            case .member:
                return nil
            }
        }
        return nil
    }

    private var canManageHousehold: Bool {
        switch currentUserRole {
        case .creator, .admin:
            return true
        case .member:
            return false
        }
    }

    private var currentUserRole: MembershipRole {
        guard
            let selectedMembershipId = appRouter.selectedMembershipId,
            let currentMembership = viewModel.members.first(where: { $0.id == selectedMembershipId })
        else {
            return .member
        }
        return currentMembership.parsedRole ?? .member
    }
}

// MARK: - Organization Settings Sheet

struct OrganizationSettingsSheet: View {
    @EnvironmentObject private var appSettings: AppSettingsManager
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var familyViewModel: FamilyViewModel
    @State private var name: String
    @State private var groupDescription: String = ""
    @State private var showDisbandConfirmation = false
    private let initialName: String
    private let initialDescription: String
    let isSubmitting: Bool
    let canDisband: Bool
    let errorMessage: String?
    let onSubmit: @MainActor (String, String) async -> Void
    let onDisband: @MainActor (String) async -> Bool

    init(
        initialName: String,
        initialDescription: String,
        familyViewModel: FamilyViewModel,
        isSubmitting: Bool,
        canDisband: Bool,
        errorMessage: String?,
        onSubmit: @escaping @MainActor (String, String) async -> Void,
        onDisband: @escaping @MainActor (String) async -> Bool
    ) {
        self.familyViewModel = familyViewModel
        _name = State(initialValue: initialName)
        self.initialName = initialName
        self.initialDescription = initialDescription
        self.isSubmitting = isSubmitting
        self.canDisband = canDisband
        self.errorMessage = errorMessage
        self.onSubmit = onSubmit
        self.onDisband = onDisband
    }

    private var isDisbanding: Bool {
        familyViewModel.isDisbanding
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedDescription: String {
        groupDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedInitialName: String {
        initialName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedInitialDescription: String {
        initialDescription.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        isSubmitting == false
            && isDisbanding == false
            && trimmedName.isEmpty == false
            && (trimmedName != normalizedInitialName || trimmedDescription != normalizedInitialDescription)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 18) {
                    organizationNameField
                    organizationDescriptionField

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    saveChangesButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                Spacer(minLength: 0)

                VStack(spacing: 18) {
                    if familyViewModel.canTransferOwnership {
                        transferOwnershipRow
                    }

                    if canDisband {
                        disbandHouseholdSection
                    } else if familyViewModel.canLeaveCurrentHousehold {
                        leaveHouseholdSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(.systemGroupedBackground))
            .onAppear {
                groupDescription = initialDescription
            }
            .navigationTitle(L10n.Family.groupSettings2.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.close) {
                        dismiss()
                    }
                    .disabled(isSubmitting || isDisbanding)
                }
            }
            .sheet(isPresented: $showDisbandConfirmation) {
                DisbandHouseholdConfirmationSheet(
                    familyViewModel: familyViewModel,
                    householdName: initialName,
                    onConfirm: { userInput in
                        await onDisband(userInput)
                    }
                )
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled(familyViewModel.isDisbanding)
            }
        }
    }

    private var organizationNameField: some View {
        TextField(AppLocalized.string(L10n.Family.enterGroupName, locale: appSettings.appLocale), text: $name)
            .textInputAutocapitalization(.words)
            .disabled(isSubmitting || isDisbanding)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var organizationDescriptionField: some View {
        TextField(AppLocalized.string(L10n.Family.enterGroupDescriptionOptional, locale: appSettings.appLocale), text: $groupDescription, axis: .vertical)
            .lineLimit(3 ... 6)
            .disabled(isSubmitting || isDisbanding)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var saveChangesButton: some View {
        Button {
            let nameSnapshot = trimmedName
            let descriptionSnapshot = trimmedDescription
            Task { @MainActor in
                await onSubmit(nameSnapshot, descriptionSnapshot)
            }
        } label: {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text(L10n.Common.saveChanges.localized)
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                canSave ? Color.accentColor : Color.accentColor.opacity(0.45),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(canSave == false)
    }

    private var transferOwnershipRow: some View {
        NavigationLink {
            TransferOwnershipView(familyViewModel: familyViewModel) {
                dismiss()
            }
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        } label: {
            settingsNavigationRow(
                title: L10n.Common.transferOwnership.localized,
                systemImage: "person.2.badge.gearshape"
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || isDisbanding)
    }

    private var disbandHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Common.dangerZone.localized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .textCase(.uppercase)

            Button(role: .destructive) {
                showDisbandConfirmation = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "trash.fill")
                        .font(.body)
                    Text(L10n.Family.dismissGroup.localized)
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isDisbanding || familyViewModel.isLeaving)

            Text(L10n.Schedule.uponDismissalAllMembersWillBeRemovedAndT.localized)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private var leaveHouseholdSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(role: .destructive) {
                familyViewModel.requestToLeave()
            } label: {
                HStack(spacing: 12) {
                    if familyViewModel.isLeaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.body)
                        Text(L10n.Family.leaveGroup.localized)
                            .font(.body.weight(.semibold))
                    }
                    Spacer(minLength: 8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(Color.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isDisbanding || familyViewModel.isLeaving)
        }
        .padding(.top, 8)
    }

    private func settingsNavigationRow(title: LocalizedStringResource, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, alignment: .center)

            Text(title)
                .font(.body)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Disband Confirmation Sheet

private struct DisbandHouseholdConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @ObservedObject var familyViewModel: FamilyViewModel
    let householdName: String
    let onConfirm: @MainActor (String) async -> Bool

    @State private var disbandInputName = ""

    private var normalizedExpectedName: String {
        householdName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedInputName: String {
        disbandInputName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var canConfirmDisband: Bool {
        familyViewModel.isDisbanding == false
            && normalizedInputName.isEmpty == false
            && normalizedInputName == normalizedExpectedName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(alignment: .leading, spacing: 18) {
                    Text(L10n.Family.disbandingCannotBeUndone.localized)
                        .font(.headline)

                    Text(L10n.Family.disbandConfirmMessage.formatted(locale: locale, householdName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField(AppLocalized.string(L10n.Family.enterGroupNameToConfirm, locale: locale), text: $disbandInputName)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)

                    Button(role: .destructive) {
                        let snapshot = disbandInputName
                        Task { @MainActor in
                            let succeeded = await onConfirm(snapshot)
                            if succeeded {
                                dismiss()
                            }
                        }
                    } label: {
                        Group {
                            if familyViewModel.isDisbanding {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.Common.confirmDismiss.localized)
                                    .font(.body.weight(.semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(canConfirmDisband == false)

                    Spacer()
                }
                .padding(20)
                .disabled(familyViewModel.isDisbanding)

                if familyViewModel.isDisbanding {
                    Color.black.opacity(0.15)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.1)
                        Text(L10n.Family.dismissingGroupPleaseWait.localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(radius: 10)
                }
            }
            .navigationTitle(L10n.Family.confirmDismissGroup.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Common.cancel) { dismiss() }
                        .disabled(familyViewModel.isDisbanding)
                }
            }
            .alert(L10n.Common.dismissFailed, isPresented: $familyViewModel.showDisbandErrorAlert) {
                Button(L10n.Common.gotIt, role: .cancel) {}
            } message: {
                Text(familyViewModel.disbandError ?? AppLocalized.string(L10n.Common.unknownErrorPleaseTryAgain, locale: locale))
            }
        }
    }
}
