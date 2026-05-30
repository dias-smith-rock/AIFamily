import SwiftUI
import PhotosUI
import CoreImage
import AVFoundation
import VisionKit
import Vision
import UIKit

#if canImport(Supabase)
import Supabase
#endif

struct OrgRoutingView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var householdName = ""
    @State private var householdDescription = ""
    @State private var inviteCode = ""
    @State private var showErrorAlert = false
    @State private var localErrorMessage: String?
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var createInputError: String?
    @State private var joinInputError: String?
    @State private var isSigningOut = false
    @State private var showScanOptions = false
    @State private var showCameraScanner = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isDecodingPhoto = false
    @State private var isJoiningFullScreenLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AppLocalized.string("请选择一种方式继续", locale: locale))
                        .font(AppTheme.FontToken.subtitle)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)

                    RouteActionCard(
                        icon: "house.fill",
                        title: AppLocalized.string("我是家长", locale: locale),
                        subtitle: AppLocalized.string("创建一个全新的群组空间", locale: locale),
                        backgroundColor: Color.orange.opacity(0.12)
                    ) {
                        createInputError = nil
                        showCreateSheet = true
                    }

                    RouteActionCard(
                        icon: "qrcode.viewfinder",
                        title: AppLocalized.string("加入群组", locale: locale),
                        subtitle: AppLocalized.string("通过扫码或邀请码加入", locale: locale),
                        backgroundColor: Color.green.opacity(0.12)
                    ) {
                        joinInputError = nil
                        showJoinSheet = true
                    }
                }
                .padding(20)
            }
            .background(AppTheme.ColorToken.background)
            .navigationTitle(AppLocalized.string("欢迎来到同圈", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await signOut() }
                    } label: {
                        if isSigningOut {
                            ProgressView()
                        } else {
                            Text(AppLocalized.string("退出登录", locale: locale))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue {
                localErrorMessage = newValue
                showErrorAlert = true
            }
        }
        .alert("操作失败", isPresented: $showErrorAlert) {
            Button("知道了", role: .cancel) {
                viewModel.acknowledgeError()
            }
        } message: {
            Text(localErrorMessage ?? "请稍后重试。")
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateHouseholdSheet(
                householdName: $householdName,
                householdDescription: $householdDescription,
                inputError: $createInputError,
                isSubmitting: viewModel.isCreating,
                onSubmit: {
                    await submitCreate()
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showJoinSheet) {
            JoinHouseholdSheet(
                inviteCode: $inviteCode,
                inputError: $joinInputError,
                isSubmitting: viewModel.isJoining,
                isDecodingPhoto: isDecodingPhoto,
                onScan: {
                    showScanOptions = true
                },
                onSubmit: {
                    await submitJoin()
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("选择识别方式", isPresented: $showScanOptions, titleVisibility: .visible) {
            Button("相机扫码") {
                showCameraScanner = true
            }
            Button("从相册识别") {
                showPhotoPicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .sheet(isPresented: $showCameraScanner) {
            QRScannerSheet { raw in
                handleRecognizedCode(raw)
                showCameraScanner = false
            } onError: { message in
                joinInputError = message
                showCameraScanner = false
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItem,
            matching: .images,
            preferredItemEncoding: .automatic
        )
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await decodeInviteCodeFromPhoto(newItem)
            }
        }
        .overlay {
            if isJoiningFullScreenLoading {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(AppLocalized.string("正在加入群组…", locale: locale))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
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

    private func handleRecognizedCode(_ raw: String) {
        guard let code = firstInviteCode(from: raw.uppercased()) else {
            joinInputError = AppLocalized.string("未识别到有效邀请码，请重试。", locale: locale)
            return
        }
        inviteCode = code
        joinInputError = nil
        Task {
            await submitJoin()
        }
    }

    private func firstInviteCode(from text: String) -> String? {
        let pattern = "\\b[A-Z0-9]{6}\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    private func decodeInviteCodeFromPhoto(_ item: PhotosPickerItem) async {
        await MainActor.run {
            isDecodingPhoto = true
            joinInputError = nil
        }
        defer {
            Task { @MainActor in
                isDecodingPhoto = false
                selectedPhotoItem = nil
            }
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let ciImage = CIImage(data: data) else {
                await MainActor.run {
                    joinInputError = AppLocalized.string("图片读取失败，请换一张清晰二维码图片。", locale: locale)
                }
                return
            }

            let detector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
            )
            let features = detector?.features(in: ciImage) as? [CIQRCodeFeature]
            let payload = features?.compactMap(\.messageString).joined(separator: " ") ?? ""

            await MainActor.run {
                handleRecognizedCode(payload)
            }
        } catch {
            await MainActor.run {
                joinInputError = AppLocalized.string("二维码识别失败，请重试。", locale: locale)
            }
        }
    }

    private func submitCreate() async {
        createInputError = nil
        guard normalizedHouseholdName.isEmpty == false else {
            createInputError = AppLocalized.string("请输入群组名称。", locale: locale)
            return
        }
        let trimmedDescription = householdDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let createdId = await viewModel.createHousehold(
            displayName: normalizedHouseholdName,
            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
            isPremium: appRouter.hasPremiumAccess
        )
        guard let createdId else { return }
        showCreateSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdId)
        appRouter.goToActiveMember()
        await appRouter.refreshStateFromBackend()
    }

    private func submitJoin() async {
        joinInputError = nil
        guard isInviteCodeValid else {
            joinInputError = String(localized: "邀请码格式无效：必须为 6 位字母或数字。")
            return
        }
        guard isJoiningFullScreenLoading == false else { return }
        isJoiningFullScreenLoading = true
        defer { isJoiningFullScreenLoading = false }

        let success = await viewModel.joinHousehold(inviteCode: normalizedInviteCode)
        guard success else { return }
        showJoinSheet = false
        await appRouter.refreshStateFromBackend()
        if let groupId = appRouter.selectedHouseholdId {
            AnalyticsManager.log(event: .groupJoined(groupId: groupId))
        }
    }

    private func signOut() async {
        guard isSigningOut == false else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        AuthSessionGuard.shared.beginLoggingOut()
        #if canImport(Supabase)
        do {
            try await SupabaseManager.shared.client.auth.signOut()
            await appRouter.refreshStateFromBackend()
        } catch {
            localErrorMessage = error.localizedDescription
            showErrorAlert = true
        }
        #else
        appRouter.appState = .unauthenticated
        #endif
        await AuthSessionGuard.shared.endLoggingOut()
    }
}

private struct RouteActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let backgroundColor: Color
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 42, height: 42)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(AppTheme.FontToken.section)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(AppTheme.FontToken.subtitle)
                        .foregroundStyle(AppTheme.ColorToken.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct CreateHouseholdSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Binding var householdName: String
    @Binding var householdDescription: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalized.string("请输入群组名称", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                TextField(AppLocalized.string("例如：王家小院", locale: locale), text: $householdName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(AppLocalized.string("输入群组描述（选填）", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                TextField(
                    AppLocalized.string("输入群组描述（选填）…", locale: locale),
                    text: $householdDescription,
                    axis: .vertical
                )
                .lineLimit(3 ... 6)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))

                if let inputError {
                    Text(inputError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await onSubmit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text(AppLocalized.string("确认创建", locale: locale))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                Spacer()
            }
            .padding(16)
            .navigationTitle(AppLocalized.string("创建群组", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized.string("关闭", locale: locale)) { dismiss() }
                }
            }
        }
    }
}

private struct JoinHouseholdSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Binding var inviteCode: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let isDecodingPhoto: Bool
    let onScan: () -> Void
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Button(action: onScan) {
                    HStack(spacing: 8) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 18, weight: .semibold))
                        Text(AppLocalized.string("扫一扫加入", locale: locale))
                            .font(.system(size: 20, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isDecodingPhoto)

                HStack(spacing: 10) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                    Text(AppLocalized.string("或", locale: locale))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                }

                TextField(AppLocalized.string("输入 6 位邀请码", locale: locale), text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 22, weight: .semibold, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                if let inputError {
                    Text(inputError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                }

                if isDecodingPhoto {
                    Label(AppLocalized.string("正在识别图片中的邀请码…", locale: locale), systemImage: "photo")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await onSubmit() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        Text(AppLocalized.string("确认加入", locale: locale))
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                Spacer()
            }
            .padding(16)
            .navigationTitle(AppLocalized.string("加入群组", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized.string("关闭", locale: locale)) { dismiss() }
                }
            }
        }
    }
}

private struct QRScannerSheet: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        guard DataScannerViewController.isSupported else {
            onError(AppLocalized.string("当前设备不支持相机扫码。", locale: .current))
            return UIViewController()
        }
        guard DataScannerViewController.isAvailable else {
            onError(AppLocalized.string("相机当前不可用，请检查权限后重试。", locale: .current))
            return UIViewController()
        }

        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        do {
            try scanner.startScanning()
        } catch {
            onError(String(localized: "无法启动扫描仪。请稍后重试。"))
        }
        return scanner
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            if case .barcode(let barcode) = item,
               let payload = barcode.payloadStringValue {
                onCode(payload)
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            guard let first = addedItems.first else { return }
            if case .barcode(let barcode) = first,
               let payload = barcode.payloadStringValue {
                onCode(payload)
            }
        }
    }
}

#Preview {
    OrgRoutingView()
        .environmentObject(AppRouter())
}
