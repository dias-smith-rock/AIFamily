import SwiftUI

/// Pro 订阅页：MVP 阶段「创世用户限时免费领取 1 年 Pro」增长策略。
struct VIPSubscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeVIPSubscriptionViewModel()
    @State private var showClaimSuccessAlert = false

    private var claimSuccessMessage: String {
        guard let expiry = viewModel.claimedExpiryDate else {
            return String(localized: "领取成功！您的 Pro 权益已激活至 2027 年。")
        }
        let year = Calendar.current.component(.year, from: expiry)
        return String(
            format: String(localized: "领取成功！您的 Pro 权益已激活至 %lld 年。"),
            year
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                heroSection
                featureCardsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("升级 VIP")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            claimButtonBar
        }
        .alert("提示", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if $0 == false { viewModel.errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(verbatim: viewModel.errorMessage ?? "")
        }
        .alert(claimSuccessMessage, isPresented: $showClaimSuccessAlert) {
            Button("好的", role: .cancel) {
                dismiss()
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

            Text("升级至 Pro 高级版")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            Text("🚀 创世用户福利：限时免费领取 1 年 Pro 权益！")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
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

    // MARK: - Feature cards

    private var featureCardsSection: some View {
        VStack(spacing: 12) {
            VIPFeatureComparisonCard(
                systemImage: "person.3.fill",
                iconTint: .blue,
                title: "群组与协作人数",
                freeDescription: "最多 1 个群组，每组上限 2 人。",
                proDescription: "👑 无限创建与加入群组，无限成员人数。"
            )

            VIPFeatureComparisonCard(
                systemImage: "photo.stack.fill",
                iconTint: .purple,
                title: "任务附件与媒体库",
                freeDescription: "每任务限 1 张压缩图片。",
                proDescription: "👑 单任务无限图片、支持原图 (Original Quality)、解锁视频与文档 (PDF/Word) 上传。"
            )

            VIPFeatureComingSoonCard(
                systemImage: "sparkles",
                iconTint: .orange,
                title: "敬请期待",
                description: "AI 语音极速建任务、群组智能周报、高阶提醒规则等更多专属功能即将上线。"
            )
        }
    }

    // MARK: - CTA

    private var claimButtonBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task {
                    let success = await viewModel.claimFreeProTrial(appRouter: appRouter)
                    if success {
                        showClaimSuccessAlert = true
                    }
                }
            } label: {
                Group {
                    if viewModel.isClaiming {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    } else {
                        Text("免费领取 1 年 Pro 权益")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
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
            .disabled(viewModel.isClaiming)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Feature comparison card

private struct VIPFeatureComparisonCard: View {
    let systemImage: String
    let iconTint: Color
    let title: LocalizedStringKey
    let freeDescription: LocalizedStringKey
    let proDescription: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 32, height: 32)
                    .background(iconTint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 10) {
                tierRow(label: "免费版", description: freeDescription, accent: .secondary)
                tierRow(label: "Pro 版", description: proDescription, accent: .orange)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }

    private func tierRow(
        label: LocalizedStringKey,
        description: LocalizedStringKey,
        accent: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(0.12), in: Capsule())

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Coming soon card

private struct VIPFeatureComingSoonCard: View {
    let systemImage: String
    let iconTint: Color
    let title: LocalizedStringKey
    let description: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconTint)
                    .frame(width: 32, height: 32)
                    .background(iconTint.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    NavigationStack {
        VIPSubscriptionView()
            .environmentObject(AppRouter())
    }
}
