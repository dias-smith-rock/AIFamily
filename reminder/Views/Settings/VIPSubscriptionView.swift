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

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection

                if appRouter.hasPremiumAccess == false {
                    planPickerSection
                }

                benefitsSection

                if appRouter.hasPremiumAccess == false {
                    subscriptionLegalNote
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(appRouter.hasPremiumAccess ? "Pro 会员" : "升级 VIP")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if appRouter.hasPremiumAccess {
                activeProStatusBar
            } else {
                subscribeButtonBar
            }
        }
        .task {
            AnalyticsManager.log(event: .vipPageViewed)
            await viewModel.loadProducts()
        }
        .alert("订阅成功", isPresented: $showPurchaseSuccessAlert) {
            Button("好的", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("Pro 会员已激活，尽情使用高级功能吧。")
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if $0 == false { viewModel.errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) { viewModel.errorMessage = nil }
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

            Text(appRouter.hasPremiumAccess ? "Pro 会员已激活" : "升级至 Pro 高级版")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Group {
                if appRouter.hasPremiumAccess {
                    Text(proActiveDetailText)
                } else {
                    Text("解锁全组高级特权，一人续费全组共享")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(appRouter.hasPremiumAccess ? Color.secondary : Color.orange)
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
            Text("选择订阅方案")
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
            Text("Premium 特权")
                .font(.headline)
                .foregroundStyle(.primary)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                VIPPremiumBenefitRow(
                    systemImage: "person.2.badge.gearshape.fill",
                    iconTint: .orange,
                    title: "一人付费，全组 VIP",
                    description: "一人续费承包全组，群组成员无缝共享全部高级特权。",
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "person.3.fill",
                    iconTint: .blue,
                    title: "无限群组与成员",
                    description: "打破建群上限，支持容纳无限成员，连接你的多重生活圈。",
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "camera.viewfinder",
                    iconTint: .cyan,
                    title: "AI 智能读图建任务",
                    description: "随手拍照即可提取核心日程，让科技为你精简群组组织成本。",
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "point.topleft.down.to.point.bottomright.filled.curvepath",
                    iconTint: .green,
                    title: "20 条位置历史轨迹",
                    description: "解锁更长、更细腻的动态足迹线，全天安全动向一手掌握。",
                    showsDivider: true
                )

                VIPPremiumBenefitRow(
                    systemImage: "location.slash.fill",
                    iconTint: .purple,
                    title: "隐私隐身模式",
                    description: "自由掌控位置共享时机，一键开启，随时切换独立隐私。",
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
            Text("订阅将自动续费，可随时在 App Store 账户设置中取消。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: 4) {
                legalLinkButton("隐私政策") {
                    showPrivacySheet = true
                }
                Text("·")
                    .foregroundStyle(.tertiary)
                legalLinkButton("用户协议") {
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
        if let expiry = appRouter.userEntitlement?.proExpiresAt, appRouter.userEntitlement?.isActive == true {
            let year = Calendar.current.component(.year, from: expiry)
            return String(
                format: AppLocalized.string("个人权益有效期至 %lld 年", locale: locale),
                locale: locale,
                year
            )
        }
        if appRouter.hasInheritedPremiumOnly {
            return AppLocalized.string("当前群组已继承 Pro 权益", locale: locale)
        }
        return AppLocalized.string("感谢您的支持，尽情使用 Pro 功能吧。", locale: locale)
    }

    private var activeProStatusBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.orange)
                Text("Pro 会员已激活")
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
                            Text("订阅 Pro")
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
                Text("恢复购买")
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
                format: AppLocalized.string("%@/月", locale: locale),
                locale: locale,
                price
            )
        case .yearly:
            return String(
                format: AppLocalized.string("%@/年", locale: locale),
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
                        Text("推荐")
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

#Preview("已订阅") {
    NavigationStack {
        VIPSubscriptionView()
            .environmentObject({
                let router = AppRouter()
                return router
            }())
    }
}
