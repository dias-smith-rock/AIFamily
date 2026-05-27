import SwiftUI
import Kingfisher
#if canImport(UIKit)
import UIKit
#endif

struct MineView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @StateObject private var viewModel = AppViewModels.makeMineViewModel()
    @StateObject private var familyViewModel = AppViewModels.makeFamilyViewModel()
    @StateObject private var authViewModel = AppViewModels.makeAuthViewModel()
    @State private var editingSelfProfile: FamilyProfile?
    @State private var isShowingLoginSheet = false
    @State private var showTermsSheet = false
    @State private var showPrivacySheet = false

    /// 与 `mineNavigationRow` 中「图标列 + 间距」一致，避免居中文字导致系统把分隔线对齐到屏幕中间。
    private static let settingsRowSeparatorLeading: CGFloat = 30 + 12

    private enum FeatureVisibility {
        static let showsVIPBanner = false
        static let showsIntegrationsSection = false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GlobalHeaderView {
                    Text("我的")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                mineSettingsList
            }
            .background(AppTheme.ColorToken.background)
            .navigationBarHidden(true)
        }
        .task {
            await viewModel.loadAccountSummary()
            familyViewModel.setHouseholdContext(appRouter.selectedHouseholdId)
            familyViewModel.setMembershipContext(appRouter.selectedMembershipId)
            await familyViewModel.loadMembers()
            isShowingLoginSheet = familyViewModel.requiresLogin
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, newValue in
            familyViewModel.setHouseholdContext(newValue)
            Task {
                await familyViewModel.loadMembers()
                isShowingLoginSheet = familyViewModel.requiresLogin
            }
        }
        .onChange(of: appRouter.selectedMembershipId) { _, newValue in
            familyViewModel.setMembershipContext(newValue)
            Task { await familyViewModel.loadMembers() }
        }
        .onChange(of: familyViewModel.requiresLogin) { _, requiresLogin in
            isShowingLoginSheet = requiresLogin
        }
        .sheet(isPresented: $isShowingLoginSheet) {
            FamilySessionLoginSheet(viewModel: authViewModel) {
                await familyViewModel.didLoginSuccessfully()
                isShowingLoginSheet = familyViewModel.requiresLogin
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.toastMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeToast() } }
        )) {
            Button("好的", role: .cancel) { viewModel.acknowledgeToast() }
        } message: {
            Text(viewModel.toastMessage ?? "")
        }
        .alert("退出失败", isPresented: Binding(
            get: { viewModel.signOutErrorMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeSignOutError() } }
        )) {
            Button("我知道了", role: .cancel) { viewModel.acknowledgeSignOutError() }
        } message: {
            Text(viewModel.signOutErrorMessage ?? "")
        }
        .alert("永久注销账号", isPresented: $viewModel.showDeleteAccountAlert) {
            Button("取消", role: .cancel) {}
            Button("确认注销", role: .destructive) {
                Task { await viewModel.deleteAccount(appRouter: appRouter) }
            }
        } message: {
            Text("此操作将永久删除您的账号及所有个人数据（创建的群组会被解散，加入的群组会被移出）。该操作不可逆，请谨慎确认。")
        }
        .alert("无法直接注销", isPresented: $viewModel.showCreatorBlockAlert) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.blockAlertMessage)
        }
        .alert("注销失败", isPresented: Binding(
            get: { viewModel.deleteAccountErrorMessage != nil },
            set: { if $0 == false { viewModel.acknowledgeDeleteAccountError() } }
        )) {
            Button("我知道了", role: .cancel) { viewModel.acknowledgeDeleteAccountError() }
        } message: {
            Text(viewModel.deleteAccountErrorMessage ?? "")
        }
        .sheet(isPresented: $showTermsSheet) {
            if let url = SupportLegalLinks.termsOfService {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showPrivacySheet) {
            if let url = SupportLegalLinks.privacyPolicy {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var mineSettingsList: some View {
        List {
            Section {
                profileHeaderRow
            }
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            if FeatureVisibility.showsVIPBanner {
                Section {
                    vipBannerRow
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [.orange.opacity(0.92), .yellow.opacity(0.88)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                )
            }

            Section {
                NavigationLink {
                    LanguageSettingsView()
                } label: {
                    SettingsRowView(
                        title: "Language",
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
                        title: "Notifications",
                        systemImage: "bell.badge.fill",
                        iconTint: .red,
                        subtitle: "Push & Sounds"
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    SettingsRowView(
                        title: "Theme",
                        systemImage: "moon.fill",
                        iconTint: .purple,
                        value: appSettings.appearance.valueTitle(locale: locale),
                        showsChevron: false
                    )
                }

                NavigationLink {
                    TextSizeSettingsView()
                } label: {
                    SettingsRowView(
                        title: "Text Size",
                        systemImage: "textformat.size",
                        iconTint: .blue,
                        showsValue: false,
                        showsChevron: false
                    )
                }
            } header: {
                mineSectionHeader("APP SETTINGS")
            }

            if FeatureVisibility.showsIntegrationsSection {
                Section {
                    mineNavigationRow(
                        title: "Integrations",
                        systemImage: "link",
                        iconTint: .orange,
                        subtitle: "FaceTime, WhatsApp"
                    ) {
                        viewModel.tapRow(feature: "集成")
                    }
                    mineNavigationRow(
                        title: "Import Events",
                        systemImage: "calendar",
                        iconTint: .green,
                        subtitle: "Sync Calendar & Public Holidays"
                    ) {
                        viewModel.tapRow(feature: "导入日程")
                    }
                } header: {
                    mineSectionHeader("INTEGRATIONS & DATA")
                }
            }

            Section {
                Button {
                    Task { await viewModel.contactSupport() }
                } label: {
                    SettingsRowView(
                        title: "Support",
                        systemImage: "lifepreserver.circle.fill",
                        iconTint: .cyan
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showTermsSheet = true
                } label: {
                    SettingsRowView(
                        title: "Terms of Service",
                        systemImage: "doc.text",
                        iconTint: Color.primary.opacity(0.55)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    showPrivacySheet = true
                } label: {
                    SettingsRowView(
                        title: "Privacy Policy",
                        systemImage: "shield",
                        iconTint: .blue
                    )
                }
                .buttonStyle(.plain)

                NavigationLink {
                    AboutView()
                } label: {
                    SettingsRowView(
                        title: "About WeFamily",
                        systemImage: "info.circle",
                        iconTint: .purple,
                        showsChevron: false
                    )
                }
            } header: {
                mineSectionHeader("SUPPORT & LEGAL")
            }

            Section {
                Button {
                    Task { await viewModel.signOut(appRouter: appRouter) }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSigningOut {
                            ProgressView()
                        } else {
                            Text("Log Out")
                                .font(AppTheme.FontToken.bodyStrong)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in Self.settingsRowSeparatorLeading }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSigningOut || viewModel.isDeletingAccount || viewModel.isCheckingCreatorStatus)

                Button(role: .destructive) {
                    Task { await viewModel.checkCreatorStatusBeforeDeletion() }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isCheckingCreatorStatus {
                            ProgressView()
                                .padding(.trailing, 4)
                            Text("Delete Account")
                                .font(AppTheme.FontToken.bodyStrong)
                        } else if viewModel.isDeletingAccount {
                            ProgressView()
                        } else {
                            Text("Delete Account")
                                .font(AppTheme.FontToken.bodyStrong)
                        }
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .alignmentGuide(.listRowSeparatorLeading) { _ in Self.settingsRowSeparatorLeading }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSigningOut || viewModel.isDeletingAccount || viewModel.isCheckingCreatorStatus)
            } header: {
                mineSectionHeader("ACCOUNT")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(AppTheme.ColorToken.background)
        .contentMargins(.top, 0, for: .scrollContent)
    }

    // MARK: - Profile header（与「家庭」成员行 / 编辑页一致）

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
            .accessibilityHint("编辑我的群组档案")
        }
    }

    private var mineHeaderMainTitle: String {
        familyViewModel.currentUserProfile?.displayName ?? viewModel.displayName
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
            viewModel.showToast("尚未载入你在当前群组的档案，请先在「群组」确认已加入群组。")
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
            .accessibilityLabel("编辑头像")
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
            return "群组成员"
        }
        switch membership.parsedRole {
        case .creator, .admin:
            return contactSubtitleLine(for: profile)
        case .member:
            return membership.parsedRole?.displayTitle ?? "成员"
        case .none:
            if profile.isVirtualUser {
                return contactSubtitleLine(for: profile)
            }
            return "群组成员"
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
            Text("创建者")
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.12))
                .foregroundStyle(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .admin:
            Text("管理员")
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
            Text("档案")
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(.tertiary)
        .accessibilityLabel("档案成员")
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

    private var vipBannerRow: some View {
        Button {
            viewModel.tapUpgradeVIP()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: "sparkle")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.45))
                        .offset(x: -10, y: -8)
                    Image(systemName: "crown.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade to VIP")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Unlock premium features")
                        .font(AppTheme.FontToken.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section chrome

    private func mineSectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mineNavigationRow(
        title: LocalizedStringKey,
        systemImage: String,
        iconTint: Color,
        subtitle: LocalizedStringKey? = nil,
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
}

#Preview {
    MineView()
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
}
