import SwiftUI

/// Pro 订阅页：方案选择、权益说明与 App Store 订阅入口。
struct VIPSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeVIPSubscriptionViewModel()
    @ObservedObject private var storeKit = StoreKitSubscriptionService.shared
    @State private var showPrivacySheet = false
    @State private var showTermsSheet = false
    @State private var showPurchaseSuccessAlert = false

    private var showsPersonalVIP: Bool {
        appRouter.showsPersonalVIP
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection

                if showsPersonalVIP == false {
                    planPickerSection
                }

                benefitsSection

                if showsPersonalVIP == false {
                    subscriptionLegalNote
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(showsPersonalVIP ? L10n.VIP.proMembership : L10n.VIP.upgradeToVip)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsPersonalVIP {
                activeProStatusBar
            } else {
                subscribeButtonBar
            }
        }
        .task {
            AnalyticsManager.log(event: .vipPageViewed)
            await viewModel.loadProducts()
            await storeKit.refreshLocalEntitlements(for: appRouter.authUserId)
        }
        .alert(L10n.VIP.subscriptionSuccessful, isPresented: $showPurchaseSuccessAlert) {
            Button(L10n.Common.ok, role: .cancel) {
                dismiss()
            }
        } message: {
            Text(L10n.VIP.proIsActiveEnjoyAllPremiumFeatures.localized)
        }
        .alert(L10n.Common.notice, isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if $0 == false { viewModel.errorMessage = nil } }
        )) {
            Button(L10n.Common.ok, role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(verbatim: viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showPrivacySheet) {
            if let url = SupportLegalLinks.privacyPolicyEnglish {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showTermsSheet) {
            if let url = SupportLegalLinks.termsOfServiceEnglish {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 56, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    Color.orange.opacity(0.35)
                )
                .padding(.top, 8)

            Text(showsPersonalVIP ? L10n.VIP.proMembershipActive : L10n.VIP.upgradeToPro)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Group {
                if showsPersonalVIP {
                    Text(proActiveDetailText)
                } else {
                    Text(L10n.Common.unlockPremiumForTheWholeGroupOneSubscript.localized)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(showsPersonalVIP ? Color.secondary : Color.orange)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    // MARK: - Plan picker

    private var planPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.VIP.chooseAPlan.localized)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                ForEach(VIPBillingPlan.allCases) { plan in
                    VIPPlanOptionCard(
                        plan: plan,
                        priceText: storeKit.displayPrice(for: plan) ?? plan.fallbackPriceText,
                        isSelected: viewModel.selectedPlan == plan
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedPlan = plan
                        }
                    }
                }
            }
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Common.premiumBenefits.localized)
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                VIPPremiumBenefitRow(
                    systemImage: "person.2.badge.gearshape.fill",
                    iconTint: .orange,
                    title: L10n.VIP.onePayerWholeGroupVip,
                    description: L10n.Family.oneRenewalCoversEveryoneGroupMembersSeamle,
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "person.3.fill",
                    iconTint: .blue,
                    title: L10n.Family.unlimitedGroupsMembers,
                    description: L10n.Common.noGroupCapsConnectEveryCircleOfYourLife,
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "camera.viewfinder",
                    iconTint: .cyan,
                    title: L10n.Schedule.aiPhotoToTask,
                    description: L10n.Schedule.snapAPhotoToExtractKeySchedulesAndSimpli,
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "point.topleft.down.to.point.bottomright.filled.curvepath",
                    iconTint: .green,
                    title: L10n.Location.n20LocationHistoryPoints,
                    description: L10n.Common.richerMovementTrailsSoYouCanTrackSafetyA,
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "location.slash.fill",
                    iconTint: .purple,
                    title: L10n.Location.privacyGhostMode,
                    description: L10n.Location.controlWhenYouShareLocationToggleGhostMod,
                    showsDivider: false
                )
            }
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
    }

    private var subscriptionLegalNote: some View {
        VStack(spacing: 8) {
            Text(L10n.VIP.subscriptionRenewsAutomaticallyCancelAnytime.localized)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                legalLinkButton(L10n.Common.privacyPolicy) {
                    showPrivacySheet = true
                }
                Text("·")
                    .foregroundStyle(.tertiary)
                legalLinkButton(L10n.Common.termsOfService) {
                    showTermsSheet = true
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func legalLinkButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .underline()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }

    // MARK: - Footer

    private var proActiveDetailText: String {
        if let expiry = storeKit.personalSubscriptionExpiry(userEntitlement: appRouter.userEntitlement) {
            let year = Calendar.current.component(.year, from: expiry)
            return String(
                format: AppLocalized.string(L10n.Common.personalBenefitsValidUntilLld, locale: locale),
                locale: locale,
                year
            )
        }
        return AppLocalized.string(L10n.VIP.thankYouForYourSupportEnjoyProFeatures, locale: locale)
    }

    private var activeProStatusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.orange)
                Text(L10n.VIP.proMembershipActive.localized)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .background(Color(.systemGroupedBackground))
        }
    }

    private var subscribeButtonBar: some View {
        VStack(spacing: 10) {
            Divider()

            Button {
                Task {
                    let success = await viewModel.purchaseSubscription(appRouter: appRouter)
                    if success {
                        showPurchaseSuccessAlert = true
                    }
                }
            } label: {
                Group {
                    if viewModel.isPurchasing {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        VStack(spacing: 4) {
                            Text(L10n.VIP.subscribeToPro.localized)
                                .font(.headline.weight(.bold))
                            Text(subscribePriceCaption)
                                .font(.subheadline.weight(.medium))
                                .opacity(0.92)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                }
                .background(
                    LinearGradient(
                        colors: [.orange, .yellow.opacity(0.92)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPurchasing)

            Button {
                Task {
                    let success = await viewModel.restorePurchases(appRouter: appRouter)
                    if success {
                        showPurchaseSuccessAlert = true
                    }
                }
            } label: {
                Text(L10n.Common.restorePurchases.localized)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPurchasing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color(.systemGroupedBackground))
    }

    private var subscribePriceCaption: String {
        let plan = viewModel.selectedPlan
        let price = viewModel.displayPrice(for: plan)
        switch plan {
        case .monthly:
            return String(
                format: AppLocalized.string(L10n.Common.mo, locale: locale),
                locale: locale,
                price
            )
        case .yearly:
            return String(
                format: AppLocalized.string(L10n.Common.yr, locale: locale),
                locale: locale,
                price
            )
        }
    }
}

// MARK: - Plan card

private struct VIPPlanOptionCard: View {
    let plan: VIPBillingPlan
    let priceText: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(plan.planTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)

                    if plan.isRecommended {
                        Text(L10n.Common.recommended.localized)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange, in: Capsule())
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(priceText)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(plan.periodLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                if let savingsBadge = plan.savingsBadge {
                    Text(savingsBadge)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                } else {
                    Text(" ")
                        .font(.caption)
                        .padding(.vertical, 4)
                        .opacity(0)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [.orange, .yellow.opacity(0.9)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            : AnyShapeStyle(Color(.separator).opacity(0.35)),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .shadow(
                color: isSelected ? Color.orange.opacity(0.18) : Color.black.opacity(0.04),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 3 : 1
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Benefit row

private struct VIPPremiumBenefitRow: View {
    let systemImage: String
    let iconTint: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 36, height: 36)
                    .background(iconTint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showsDivider {
                Divider()
                    .padding(.leading, 66)
            }
        }
    }
}

#Preview("未订阅") {
    NavigationStack {
        VIPSubscriptionView()
            .environmentObject(AppRouter())
    }
}

#Preview(L10n.VIP.subscribed) {
    NavigationStack {
        VIPSubscriptionView()
            .environmentObject({
                let router = AppRouter()
                return router
            }())
    }
}
