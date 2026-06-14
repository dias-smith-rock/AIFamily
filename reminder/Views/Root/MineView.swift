import SwiftUI
import Kingfisher
#if canImport(UIKit)
import UIKit
#endif

struct MineView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject private var revenueCat = RevenueCatSubscriptionService.shared
    @EnvironmentObject private var appBootstrap: AppBootstrap
    @EnvironmentObject private var appSettings: AppSettingsManager
    @AppStorage("isUserLoggedIn") private var isUserLoggedIn = false
    @AppStorage("requireFaceID") private var requireFaceID = false
    @AppStorage(BackgroundLocationPreferences.storageKey) private var backgroundLocationEnabled = true
    @ObservedObject private var backgroundLocationCoordinator = BackgroundLocationCoordinator.shared
    @ObservedObject private var authSessionGuard = AuthSessionGuard.shared
    @StateObject private var viewModel = AppViewModels.makeMineViewModel()
    @StateObject private var familyViewModel = AppViewModels.makeFamilyViewModel()
    @State private var editingSelfProfile: FamilyProfile?
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false

    /// 与 `mineNavigationRow` 中「图标列 + 间距」一致，避免居中文字导致系统把分隔线对齐到屏幕中间。
    private static let settingsRowSeparatorLeading: CGFloat = 30 + 12

    private enum FeatureVisibility {
        static let showsVIPEntry = true
        static let showsIntegrationsSection = false
    }

    private var showsVIPEntryForCurrentUser: Bool {
        FeatureVisibility.showsVIPEntry && isUserLoggedIn
    }

    var body: some View {
        mineNavigationWithLifecycle
            .alert(L10n.Common.notice, isPresented: toastAlertBinding) {
                Button(L10n.Common.ok, role: .cancel) { viewModel.acknowledgeToast() }
            } message: {
                Text(verbatim: viewModel.toastMessage ?? "")
            }
            .alert(L10n.Common.exitFailed, isPresented: signOutErrorAlertBinding) {
                Button(L10n.Common.gotIt, role: .cancel) { viewModel.acknowledgeSignOutError() }
            } message: {
                Text(verbatim: viewModel.signOutErrorMessage ?? "")
            }
            .alert(L10n.Common.deleteAccount, isPresented: $viewModel.showDeleteAccountAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.deleteAccount2, role: .destructive) {
                    Task {
                        authSessionGuard.beginLoggingOut()
                        familyViewModel.prepareForSignOut()
                        await viewModel.deleteAccount(appRouter: appRouter)
                    }
                }
            } message: {
                Text(L10n.Family.thisOperationWillPermanentlyDeleteYourAcco.localized)
            }
            .alert(L10n.Common.cannotDeleteAccount, isPresented: $viewModel.showCreatorBlockAlert) {
                Button(L10n.Common.gotIt, role: .cancel) {}
                Button(L10n.Family.groupSettings) {
                    appRouter.requestOpenGroupSettings()
                }
            } message: {
                Text(L10n.Settings.deleteAccountCreatorBlock.formatted(locale: locale, viewModel.creatorBlockGroupName, viewModel.creatorBlockGroupCount))
            }
            .mineSecondaryAlerts(
                viewModel: viewModel,
                showTermsSheet: $showTermsSheet,
                showPrivacySheet: $showPrivacySheet
            )
    }

    private var toastAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.toastMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeToast() } }
        )
    }

    private var signOutErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.signOutErrorMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeSignOutError() } }
        )
    }

    private var mineNavigationWithLifecycle: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView {
                    Text(L10n.Common.mine.localized)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                mineSettingsList
            }
            .background(AppTheme.ColorToken.background)
            .navigationBarHidden(true)
        }
        .environment(\.locale, appSettings.appLocale)
        .task {
            await viewModel.loadAccountSummary()
            familyViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            familyViewModel.setMembershipContext(appRouter.selectedMembershipId)
            await familyViewModel.loadMembers()
            await handleRequiresLoginIfNeeded()
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            familyViewModel.setHouseholdContext(newValue)
            Task {
                await familyViewModel.loadMembers()
                await handleRequiresLoginIfNeeded()
            }
        }
        .onChange(of: appRouter.selectedMembershipId) { _, newValue in
            familyViewModel.setMembershipContext(newValue)
            Task { await familyViewModel.loadMembers() }
        }
        .onChange(of: familyViewModel.requiresLogin) { _, needsLogin in
            guard needsLogin else { return }
            Task { await handleRequiresLoginIfNeeded() }
        }
        .fullScreenCover(item: $editingSelfProfile) { profile in
            ProfileEditView(
                mode: .edit(profile),
                householdId: appRouter.selectedHouseholdId,
                canEdit: familyViewModel.canEditProfile(profile),
                uploadAvatar: { data, profileId in
                    #if DEBUG
                    print("🔎 [MineDebug] uploadAvatar bytes=\(data.count)")
                    #endif
                    return await familyViewModel.uploadAvatar(data: data, profileId: profileId)
                },
                onSave: { _, draft in
                    await familyViewModel.updateProfile(profile, draft: draft)
                }
            )
            .environment(\.locale, appSettings.appLocale)
            .environment(\.layoutDirection, appSettings.layoutDirection)
        }
    }

    @ViewBuilder
    private var mineSettingsList: some View {
        List {
            if appRouter.isAnonymousUser {
                Section {
                    AnonymousAccountLinkCard {
                        Task { await appRouter.refreshStateFromBackend() }
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                profileHeaderRow
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            if showsVIPEntryForCurrentUser {
                Section {
                    NavigationLink {
                        VIPSubscriptionView()
                    } label: {
                        vipUpgradeRowLabel
                    }
                }
            }

            Section {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    SettingsRowView(
                        title: L10n.Common.language,
                        systemImage: "globe",
                        iconTint: .blue,
                        value: appSettings.selectedLanguage.nativeName,
                        showsChevron: false
                    )
                }

                Button {
                    #if canImport(UIKit)
                    SystemSettingsHelper.openAppSettings()
                    #endif
                } label: {
                    SettingsRowView(
                        title: L10n.Common.notifications,
                        systemImage: "bell.badge.fill",
                        iconTint: .red,
                        subtitle: L10n.Common.pushSounds
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRowView(
                        title: L10n.Common.theme,
                        systemImage: "moon.fill",
                        iconTint: .purple,
                        valueKey: appSettings.appearance.localizedName,
                        showsChevron: false
                    )
                }

                NavigationLink {
                    TextSizeSettingsView()
                } label: {
                    SettingsRowView(
                        title: L10n.Common.textSize,
                        systemImage: "textformat.size",
                        iconTint: .blue,
                        showsValue: false,
                        showsChevron: false
                    )
                }

                HStack(spacing: 12) {
                    Image(systemName: "faceid")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.mint)
                        .frame(width: 30, height: 30)
                        .background(Color.mint.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    Text(L10n.Common.requireFaceId.localized)
                        .font(AppTheme.FontToken.bodyStrong)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 8)

                    Toggle("", isOn: $requireFaceID)
                        .labelsHidden()
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(AppLocalized.string(L10n.Common.requireFaceId, locale: locale))

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 30, height: 30)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                        Text(L10n.Common.backgroundLocation.localized)
                            .font(AppTheme.FontToken.bodyStrong)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        Toggle("", isOn: $backgroundLocationEnabled)
                            .labelsHidden()
                    }
                    .contentShape(Rectangle())
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(AppLocalized.string(L10n.Common.backgroundLocation, locale: locale))

                    if backgroundLocationEnabled, backgroundLocationCoordinator.needsAlwaysPermission {
                        Text(L10n.Location.setLocationToAlwaysInSettingsToUpdateYou.localized)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 42)
                    }
                }
                .onChange(of: backgroundLocationEnabled) { _, enabled in
                    Task {
                        await backgroundLocationCoordinator.setEnabled(enabled)
                    }
                }

                NavigationLink {
                    LocationPersistSettingsView()
                } label: {
                    SettingsRowView(
                        title: L10n.Settings.locationReportingNavTitle,
                        systemImage: "mappin.and.ellipse",
                        iconTint: .teal,
                        value: LocationPersistPreferences.summaryValue(locale: locale),
                        showsChevron: false
                    )
                }
            } header: {
                mineSectionHeader(L10n.Common.appSettings)
            }

            if FeatureVisibility.showsIntegrationsSection {
                Section {
                    mineNavigationRow(
                        title: L10n.Common.integrations,
                        systemImage: "link",
                        iconTint: .orange,
                        subtitle: L10n.Common.facetimeWhatsapp
                    ) {
                        viewModel.tapRow(feature: AppLocalized.string(L10n.Common.integrations, locale: locale))
                    }
                    mineNavigationRow(
                        title: L10n.Schedule.importEvents,
                        systemImage: "calendar",
                        iconTint: .green,
                        subtitle: L10n.Common.syncCalendarPublicHolidays
                    ) {
                        viewModel.tapRow(feature: AppLocalized.string(L10n.Schedule.importEvents, locale: locale))
                    }
                } header: {
                    mineSectionHeader(L10n.Common.integrationsData)
                }
            }

            Section {
                Button {
                    Task { await viewModel.contactSupport() }
                } label: {
                    SettingsRowView(
                        title: L10n.Common.support,
                        systemImage: "lifepreserver.circle.fill",
                        iconTint: .cyan
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showTermsSheet = true
                } label: {
                    SettingsRowView(
                        title: L10n.Common.termsOfService,
                        systemImage: "doc.text",
                        iconTint: Color.primary.opacity(0.55)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showPrivacySheet = true
                } label: {
                    SettingsRowView(
                        title: L10n.Common.privacyPolicy,
                        systemImage: "shield",
                        iconTint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AboutView()
                } label: {
                    SettingsRowView(
                        title: L10n.Common.aboutWesync,
                        systemImage: "info.circle",
                        iconTint: .purple,
                        showsChevron: false
                    )
                }
            } header: {
                mineSectionHeader(L10n.Common.supportLegal)
            }

            Section {
                if appRouter.isAnonymousUser == false {
                Button {
                    Task {
                        authSessionGuard.beginLoggingOut()
                        familyViewModel.prepareForSignOut()
                        await viewModel.signOut(appRouter: appRouter)
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSigningOut {
                            ProgressView()
                        } else {
                            Text(L10n.Auth.logOut)
                                .font(AppTheme.FontToken.bodyStrong)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { _ in Self.settingsRowSeparatorLeading }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSigningOut || viewModel.isDeletingAccount || viewModel.isCheckingCreatorStatus)
                }

                if appRouter.isAnonymousUser == false {
                Button(role: .destructive) {
                    Task { await viewModel.checkCreatorStatusBeforeDeletion() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCheckingCreatorStatus {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text(L10n.Common.deleteAccount.localized)
                                .font(AppTheme.FontToken.bodyStrong)
                        } else if viewModel.isDeletingAccount {
                            ProgressView()
                        } else {
                            Text(L10n.Common.deleteAccount.localized)
                                .font(AppTheme.FontToken.bodyStrong)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .alignmentGuide(.listRowSeparatorLeading) { _ in Self.settingsRowSeparatorLeading }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSigningOut || viewModel.isDeletingAccount || viewModel.isCheckingCreatorStatus)
                }
            } header: {
                mineSectionHeader(L10n.Common.account)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - Profile header（与「群组」成员行 / 编辑页一致）

    private var profileHeaderRow: some View {
        HStack(spacing: 14) {
            profileAvatarWithCameraBadge

            Button {
                openSelfProfileEditor()
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .center, spacing: 6) {
                            Text(mineHeaderMainTitle)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)

                            if let profile = familyViewModel.currentUserProfile,
                               let role = prominentListRole(for: profile) {
                                mineRoleCapsule(role)
                            }

                            if let profile = familyViewModel.currentUserProfile, profile.isVirtualUser {
                                mineLocalProfileBadge
                            }
                        }

                        if mineHeaderSubtitle.isEmpty == false {
                            Text(mineHeaderSubtitle)
                                .font(AppTheme.FontToken.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(AppLocalized.string(L10n.Family.editMyGroupProfile, locale: locale))
        }
    }

    private var mineHeaderMainTitle: String {
        if let profile = familyViewModel.currentUserProfile {
            let raw = profile.membershipNickname ?? profile.profileName ?? profile.name
            return StoredDisplayNameResolver.selfName(raw, locale: locale)
        }
        return StoredDisplayNameResolver.selfName(viewModel.displayName, locale: locale)
    }

    private var mineHeaderSubtitle: String {
        guard let profile = familyViewModel.currentUserProfile else {
            return viewModel.email
        }
        let roleLine = memberListSubtitle(for: profile)
        if roleLine.isEmpty == false {
            return roleLine
        }
        return profile.profileContactSummaryForDisplay.isEmpty
            ? (profile.profileEmailForDisplay ?? viewModel.email)
            : profile.profileContactSummaryForDisplay
    }

    private func openSelfProfileEditor() {
        guard let profile = familyViewModel.currentUserProfile else {
            viewModel.showToast(AppLocalized.string(L10n.Settings.profileNotLoadedInGroup, locale: locale))
            return
        }
        editingSelfProfile = profile
    }

    private var profileAvatarWithCameraBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            mineHeaderAvatar
                .frame(width: 56, height: 56)
                .clipShape(Circle())

            Button {
                openSelfProfileEditor()
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(AppTheme.ColorToken.accent))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: 4)
            .accessibilityLabel(AppLocalized.string(L10n.Common.editAvatar, locale: locale))
        }
    }

    @ViewBuilder
    private var mineHeaderAvatar: some View {
        if let profile = familyViewModel.currentUserProfile {
            if let avatarURLString = profile.avatarUrl,
               let avatarURL = URL(string: avatarURLString) {
                KFImage.url(avatarURL)
                    .placeholder { ProgressView() }
                    .cacheMemoryOnly(false)
                    .resizable()
                    .scaledToFill()
            } else {
                mineAvatarFallback(for: profile)
            }
        } else if familyViewModel.isLoading, familyViewModel.hasLoadedOnce == false {
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                ProgressView()
            }
        } else {
            ZStack {
                Circle()
                    .fill(AppTheme.ColorToken.accent)
                Text(viewModel.avatarInitials)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func mineAvatarFallback(for profile: FamilyProfile) -> some View {
        let initial = profile.displayName.first.map(String.init) ?? "?"
        return Text(initial)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MineAvatarPalette.background(for: profile.id))
    }

    private func resolvedMembership(for profile: FamilyProfile) -> HouseholdMembership? {
        profile.primaryMembership ?? familyViewModel.membership(for: profile)
    }

    private func memberListSubtitle(for profile: FamilyProfile) -> String {
        let membership = resolvedMembership(for: profile)
        guard let membership else {
            if profile.isVirtualUser {
                return contactSubtitleLine(for: profile)
            }
            return AppLocalized.string(L10n.Family.groupMembers, locale: locale)
        }
        switch membership.parsedRole {
        case .creator, .admin:
            return contactSubtitleLine(for: profile)
        case .member:
            return membership.parsedRole?.displayTitle ?? AppLocalized.string(L10n.Family.member, locale: locale)
        case .none:
            if profile.isVirtualUser {
                return contactSubtitleLine(for: profile)
            }
            return AppLocalized.string(L10n.Family.groupMembers, locale: locale)
        }
    }

    private func contactSubtitleLine(for profile: FamilyProfile) -> String {
        profile.profileContactSummaryForDisplay
    }

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

    @ViewBuilder
    private func mineRoleCapsule(_ role: MembershipRole) -> some View {
        switch role {
        case .creator:
            Text(role.localizedName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .admin:
            Text(role.localizedName)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.14))
                .foregroundStyle(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .member:
            EmptyView()
        }
    }

    private var mineLocalProfileBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "icloud")
                .font(.caption2.weight(.medium))
            Text(AppLocalized.string(L10n.Common.profile, locale: locale))
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .accessibilityLabel(AppLocalized.string(L10n.Family.profileMember, locale: locale))
    }

    private enum MineAvatarPalette {
        static let colors: [Color] = [
            Color.blue.opacity(0.68),
            Color.indigo.opacity(0.64),
            Color.purple.opacity(0.62),
            Color.pink.opacity(0.62),
            Color.teal.opacity(0.66),
            Color.green.opacity(0.62),
            Color.orange.opacity(0.72),
            Color.red.opacity(0.58),
            Color.brown.opacity(0.62),
            Color.cyan.opacity(0.66),
        ]

        static func background(for id: UUID) -> Color {
            let hex = id.uuidString.replacingOccurrences(of: "-", with: "")
            let tail = String(hex.suffix(8))
            let index: Int
            if let parsed = Int(tail, radix: 16) {
                index = parsed % colors.count
            } else {
                let fallback = hex.reduce(0) { partial, character in
                    partial + (character.hexDigitValue.map { $0 } ?? 0)
                }
                index = fallback % colors.count
            }
            return colors[index]
        }
    }

    // MARK: - VIP

    private var showsPersonalVIP: Bool {
        appRouter.showsPersonalVIP
    }

    private var vipUpgradeRowLabel: some View {
        HStack(spacing: 12) {
            Image(systemName: "crown.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 30, height: 30)
                .background(Color.orange.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                if showsPersonalVIP {
                    Text(L10n.VIP.proMembership.localized)
                        .font(AppTheme.FontToken.bodyStrong)
                        .foregroundStyle(.primary)
                    Text(vipActiveSubtitle)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.VIP.upgradeToPro.localized)
                        .font(AppTheme.FontToken.bodyStrong)
                        .foregroundStyle(.primary)
                    Text(L10n.VIP.onePayerWholeGroupVip.localized)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsPersonalVIP {
                Text(L10n.VIP.subscribed.localized)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
        }
        .contentShape(Rectangle())
        .task {
            await revenueCat.refreshCustomerInfo()
        }
    }

    private var vipActiveSubtitle: String {
        if let expiry = revenueCat.personalSubscriptionExpiry(userEntitlement: appRouter.userEntitlement),
           appRouter.showsPersonalVIP {
            let year = Calendar.current.component(.year, from: expiry)
            return String(
                format: AppLocalized.string(L10n.Common.activeUntilLld, locale: locale),
                locale: locale,
                year
            )
        }
        return AppLocalized.string(L10n.VIP.proMembershipActive, locale: locale)
    }

    // MARK: - Section chrome

    private func mineSectionHeader(_ title: L10n.Entry) -> some View {
        Text(title.localized)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mineNavigationRow(
        title: L10n.Entry,
        systemImage: String,
        iconTint: Color,
        subtitle: L10n.Entry? = nil,
        value: String? = nil,
        showsValue: Bool = true,
        showsSubtitle: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        mineNavigationRow(
            title: title.localized,
            systemImage: systemImage,
            iconTint: iconTint,
            subtitle: subtitle?.localized,
            value: value,
            showsValue: showsValue,
            showsSubtitle: showsSubtitle,
            action: action
        )
    }

    private func mineNavigationRow(
        title: LocalizedStringResource,
        systemImage: String,
        iconTint: Color,
        subtitle: LocalizedStringResource? = nil,
        value: String? = nil,
        showsValue: Bool = true,
        showsSubtitle: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 30, height: 30)
                    .background(iconTint.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(AppTheme.FontToken.bodyStrong)
                        .foregroundStyle(.primary)
                    if showsSubtitle, let subtitle {
                        Text(subtitle)
                            .font(AppTheme.FontToken.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsValue, let value, value.isEmpty == false {
                    Text(value)
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func handleRequiresLoginIfNeeded() async {
        guard familyViewModel.requiresLogin else { return }
        guard authSessionGuard.isLoggingOut == false else {
            familyViewModel.clearRequiresLogin()
            return
        }
        familyViewModel.clearRequiresLogin()
        await appRouter.refreshStateFromBackend()
    }
}

private extension View {
    func mineSecondaryAlerts(
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

#Preview {
    MineView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
}
