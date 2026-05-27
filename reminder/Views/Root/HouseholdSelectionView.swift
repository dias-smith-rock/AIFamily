import SwiftUI
import PhotosUI
import CoreImage
import VisionKit
import Vision
import UIKit

#if canImport(Supabase)
import Supabase
#endif

/// 组织选择与管理枢纽：展示已加入家庭、创建新家庭、扫码/邀请码加入。
struct HouseholdSelectionView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @StateObject private var viewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var householdName = ""
    @State private var inviteCode = ""
    @State private var showErrorAlert = false
    @State private var localErrorMessage: String?
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var createInputError: String?
    @State private var joinInputError: String?
    @State private var showAuthErrorAlert = false
    @State private var showScanOptions = false
    @State private var showCameraScanner = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isDecodingPhoto = false
    @State private var isJoiningFullScreenLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection
                    coreListSection
                    bottomActionSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AppLocalized.string("群组", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewModel.showSignOutAlert = true
                        } label: {
                            Label(AppLocalized.string("退出登录", locale: locale), systemImage: "rectangle.portrait.and.arrow.right")
                        }

                        Button(role: .destructive) {
                            viewModel.showDeleteAccountAlert = true
                        } label: {
                            Label(AppLocalized.string("永久注销账号", locale: locale), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .disabled(viewModel.isProcessingAuth)
                }
            }
        }
        .task {
            await viewModel.fetchMyHouseholds(appRouter: appRouter)
        }
        .onChange(of: appRouter.appState) { _, newState in
            guard newState == .orgRouting || newState == .householdSelection else { return }
            Task {
                await viewModel.fetchMyHouseholds(appRouter: appRouter)
            }
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            if let newValue {
                localErrorMessage = newValue
                showErrorAlert = true
            }
        }
        .alert(String(localized: "Operation failed"), isPresented: $showErrorAlert) {
            Button(String(localized: "Got it"), role: .cancel) {
                viewModel.acknowledgeError()
            }
        } message: {
            Text(localErrorMessage ?? String(localized: "Please try again later."))
        }
        .alert(AppLocalized.string("退出登录", locale: locale), isPresented: $viewModel.showSignOutAlert) {
            Button(AppLocalized.string("取消", locale: locale), role: .cancel) {}
            Button(AppLocalized.string("退出", locale: locale), role: .destructive) {
                Task {
                    let succeeded = await viewModel.signOut(appRouter: appRouter)
                    if succeeded == false, viewModel.authErrorMessage != nil {
                        showAuthErrorAlert = true
                    }
                }
            }
        } message: {
            Text(AppLocalized.string("确定要退出当前账号吗？", locale: locale))
        }
        .alert(AppLocalized.string("永久注销账号", locale: locale), isPresented: $viewModel.showDeleteAccountAlert) {
            Button(AppLocalized.string("取消", locale: locale), role: .cancel) {}
            Button(AppLocalized.string("确认注销", locale: locale), role: .destructive) {
                Task {
                    let succeeded = await viewModel.deleteAccount(appRouter: appRouter)
                    if succeeded == false, viewModel.authErrorMessage != nil {
                        showAuthErrorAlert = true
                    }
                }
            }
        } message: {
            Text(AppLocalized.string("此操作将永久删除您的账号及所有个人数据（创建的群组会被解散，加入的群组会被移出）。该操作不可逆，请谨慎确认。", locale: locale))
        }
        .alert(AppLocalized.string("账号操作失败", locale: locale), isPresented: $showAuthErrorAlert) {
            Button(AppLocalized.string("知道了", locale: locale), role: .cancel) {
                viewModel.authErrorMessage = nil
            }
        } message: {
            Text(viewModel.authErrorMessage ?? AppLocalized.string("请稍后重试", locale: locale))
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateHouseholdSheet(
                householdName: $householdName,
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
        .confirmationDialog(AppLocalized.string("选择识别方式", locale: locale), isPresented: $showScanOptions, titleVisibility: .visible) {
            Button(AppLocalized.string("相机扫码", locale: locale)) {
                showCameraScanner = true
            }
            Button(AppLocalized.string("从相册识别", locale: locale)) {
                showPhotoPicker = true
            }
            Button(AppLocalized.string("取消", locale: locale), role: .cancel) {}
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
            if isJoiningFullScreenLoading || viewModel.isProcessingAuth {
                ZStack {
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                    VStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text(
                            viewModel.isProcessingAuth
                                ? AppLocalized.string("正在处理账号操作…", locale: locale)
                                : AppLocalized.string("正在加入群组…", locale: locale)
                        )
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

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("From chaos to clarity.")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Together, perfectly synced.")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var coreListSection: some View {
        if viewModel.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text(AppLocalized.string("正在加载您的群组…", locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if viewModel.joinedHouseholds.isEmpty {
            emptyHouseholdsPlaceholder
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalized.string("我的群组", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(viewModel.joinedHouseholds) { joined in
                    JoinedHouseholdCard(joined: joined) {
                        appRouter.chooseJoinedHousehold(joined)
                    }
                }
            }
        }
    }

    private var emptyHouseholdsPlaceholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text(AppLocalized.string("您还没有加入任何群组", locale: locale))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(AppLocalized.string("创建新群组，或通过邀请码加入他人已有的空间。", locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding(.horizontal, 8)
    }

    private var bottomActionSection: some View {
        VStack(spacing: 12) {
            Button {
                createInputError = nil
                showCreateSheet = true
            } label: {
                Label(AppLocalized.string("创建新群组", locale: locale), systemImage: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                joinInputError = nil
                showJoinSheet = true
            } label: {
                Label(AppLocalized.string("扫码 / 邀请码加入", locale: locale), systemImage: "qrcode.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }

    // MARK: - Actions

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
        let createdId = await viewModel.createHousehold(displayName: normalizedHouseholdName)
        guard let createdId else { return }
        showCreateSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdId)
        appRouter.goToActiveMember()
        await appRouter.refreshStateFromBackend()
        await viewModel.fetchMyHouseholds(appRouter: appRouter)
    }

    private func submitJoin() async {
        joinInputError = nil
        guard isInviteCodeValid else {
            joinInputError = String(localized: "Invalid invite code format: must be 6 letters or digits.")
            return
        }
        guard isJoiningFullScreenLoading == false else { return }
        isJoiningFullScreenLoading = true
        defer { isJoiningFullScreenLoading = false }

        let success = await viewModel.joinHousehold(inviteCode: normalizedInviteCode)
        guard success else { return }
        showJoinSheet = false
        await appRouter.refreshStateFromBackend()
        await viewModel.fetchMyHouseholds(appRouter: appRouter)
    }
}

// MARK: - Card

private struct JoinedHouseholdCard: View {
    let joined: JoinedHousehold
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: "house.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(joined.displayHouseholdName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(joined.roleDisplayTitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sheets (reuse from组织路由)

private struct CreateHouseholdSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Binding var householdName: String
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
            onError(String(localized: "Could not start scanner. Please try again later."))
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
    HouseholdSelectionView()
        .environmentObject(AppRouter())
}
