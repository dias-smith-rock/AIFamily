import SwiftUI
import PhotosUI
import CoreImage
import VisionKit
import Vision
import UIKit

#if canImport(Supabase)
import Supabase
#endif

/// 组织选择与管理枢纽：展示已加入群组、创建新群组、扫码/邀请码加入。
struct HouseholdSelectionView: View {
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
    @State private var showAuthErrorAlert = false
    @State private var showScanOptions = false
    @State private var showCameraScanner = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isDecodingPhoto = false
    @State private var isJoiningFullScreenLoading = false
    @State private var showGuestExitDialog = false
    @State private var showLinkAccountSheet = false
    @State private var isGuestExitProcessing = false

    var body: some View {
        householdNavigationStack
            .task {
                await viewModel.fetchMyHouseholds(appRouter: appRouter)
                enterSoleHouseholdIfNeeded()
            }
            .onChange(of: appRouter.appState) { _, newState in
                guard newState == .orgRouting || newState == .householdSelection else { return }
                Task {
                    await viewModel.fetchMyHouseholds(appRouter: appRouter)
                    enterSoleHouseholdIfNeeded()
                }
            }
            .onChange(of: viewModel.errorMessage) { _, newValue in
                if let newValue {
                    localErrorMessage = newValue
                    showErrorAlert = true
                }
            }
            .alert(L10n.Common.operationFailed, isPresented: $showErrorAlert) {
                Button(L10n.Common.gotIt, role: .cancel) {
                    viewModel.acknowledgeError()
                }
            } message: {
                Text(localErrorMessage ?? AppLocalized.string(L10n.Common.pleaseTryAgainLater, locale: locale))
            }
            .alert(L10n.Auth.logOut, isPresented: registeredSignOutAlertBinding) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.quit, role: .destructive) {
                    Task {
                        let succeeded = await viewModel.signOut(appRouter: appRouter)
                        if succeeded == false, viewModel.authErrorMessage != nil {
                            showAuthErrorAlert = true
                        }
                    }
                }
            } message: {
                Text(L10n.Common.areYouSureYouWantToLogOutOfYourCurrent.localized)
            }
            .guestSessionExitDialogs(
                showGuestExitDialog: $showGuestExitDialog,
                showLinkAccountSheet: $showLinkAccountSheet,
                isProcessing: $isGuestExitProcessing,
                onError: { message in
                    viewModel.authErrorMessage = message
                    showAuthErrorAlert = true
                }
            )
            .alert(L10n.Common.deleteAccount, isPresented: $viewModel.showDeleteAccountAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.deleteAccount2, role: .destructive) {
                    Task {
                        let succeeded = await viewModel.deleteAccount(appRouter: appRouter)
                        if succeeded == false, viewModel.authErrorMessage != nil {
                            showAuthErrorAlert = true
                        }
                    }
                }
            } message: {
                Text(L10n.Family.thisOperationWillPermanentlyDeleteYourAcco.localized)
            }
            .alert(L10n.Common.accountOperationFailed, isPresented: $showAuthErrorAlert) {
                Button(L10n.Common.gotIt, role: .cancel) {
                    viewModel.authErrorMessage = nil
                }
            } message: {
                Text(viewModel.authErrorMessage ?? AppLocalized.string(L10n.Common.pleaseTryAgainLater, locale: locale))
            }
            .sheet(isPresented: $showCreateSheet) { householdCreateSheet }
            .sheet(isPresented: $showJoinSheet) { householdJoinSheet }
            .confirmationDialog(L10n.Common.selectIdentificationMethod.localized, isPresented: $showScanOptions, titleVisibility: .visible) {
                Button(L10n.Common.cameraScanCode) {
                    showCameraScanner = true
                }
                Button(L10n.Common.library) {
                    showPhotoPicker = true
                }
                Button(L10n.Common.cancel, role: .cancel) {}
            }
            .forcesNonPopoverDialogPresentation()
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
                    householdLoadingOverlay
                }
            }
    }

    private var householdNavigationStack: some View {
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
            .navigationTitle(AppLocalized.string(L10n.Family.groups, locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    householdAccountMenu
                }
            }
        }
    }

    private var registeredSignOutAlertBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showSignOutAlert && appRouter.isAnonymousUser == false },
            set: { viewModel.showSignOutAlert = $0 }
        )
    }

    private var householdAccountMenu: some View {
        Menu {
            Button {
                if appRouter.isAnonymousUser {
                    showGuestExitDialog = true
                } else {
                    viewModel.showSignOutAlert = true
                }
            } label: {
                Label(
                    AppLocalized.string(
                        appRouter.isAnonymousUser ? L10n.Auth.returnToLogin : L10n.Auth.logOut,
                        locale: locale
                    ),
                    systemImage: "rectangle.portrait.and.arrow.right"
                )
            }

            if appRouter.isAnonymousUser == false {
                Button(role: .destructive) {
                    viewModel.showDeleteAccountAlert = true
                } label: {
                    Label(L10n.Common.deleteAccount.localized, systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
                .font(.title2)
                .foregroundStyle(.primary)
        }
        .disabled(viewModel.isProcessingAuth)
    }

    private var householdLoadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(
                    viewModel.isProcessingAuth
                        ? AppLocalized.string(L10n.Common.processingAccountOperations, locale: locale)
                        : AppLocalized.string(L10n.Family.joiningGroup, locale: locale)
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

    private var householdCreateSheet: some View {
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

    private var householdJoinSheet: some View {
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

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.Common.fromChaosToClarity.localized)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
            Text(L10n.Common.togetherPerfectlySynced.localized)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var coreListSection: some View {
        if viewModel.isLoading && displayedHouseholds.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text(AppLocalized.string(L10n.Family.loadingYourGroups, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if displayedHouseholds.isEmpty {
            emptyHouseholdsPlaceholder
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalized.string(L10n.Family.myGroups, locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                ForEach(displayedHouseholds) { joined in
                    JoinedHouseholdCard(joined: joined) {
                        appRouter.chooseJoinedHousehold(joined)
                    }
                }
            }
        }
    }

    /// 列表优先用 RPC 详情；若详情为空则回退 AppRouter 已拉到的组织（避免新设备误显示空引导）。
    private var displayedHouseholds: [JoinedHousehold] {
        if viewModel.joinedHouseholds.isEmpty == false {
            return viewModel.joinedHouseholds
        }
        return appRouter.selectableHouseholds.map { option in
            JoinedHousehold(
                id: option.membershipId,
                householdId: option.id,
                profileId: option.profileId,
                role: nil,
                isTrackedDevice: option.isTrackedDevice,
                household: HouseholdBasicInfo(
                    id: option.id,
                    name: option.name,
                    status: "active",
                    isPremium: option.creatorHasActivePro
                )
            )
        }
    }

    private func enterSoleHouseholdIfNeeded() {
        guard appRouter.appState == .householdSelection || appRouter.selectedHouseholdId == nil else { return }
        let households = displayedHouseholds
        guard households.count == 1, let only = households.first else { return }
        appRouter.chooseJoinedHousehold(only)
    }

    private var emptyHouseholdsPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Color.orange.opacity(0.85))
                .symbolRenderingMode(.hierarchical)
            Text(AppLocalized.string(L10n.Family.orgOnboardingTitle, locale: locale))
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
            Text(AppLocalized.string(L10n.Family.orgOnboardingSubtitle, locale: locale))
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
                Label(AppLocalized.string(L10n.Family.createNewGroup, locale: locale), systemImage: "plus.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            Button {
                joinInputError = nil
                showJoinSheet = true
            } label: {
                Label(AppLocalized.string(L10n.Family.scanCodeInviteCodeToJoin, locale: locale), systemImage: "qrcode.viewfinder")
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
            joinInputError = AppLocalized.string(L10n.Family.noValidInviteCodeDetected, locale: locale)
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
                    joinInputError = AppLocalized.string(L10n.Family.qrImageReadFailed, locale: locale)
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
                joinInputError = AppLocalized.string(L10n.Common.qrRecognitionFailedRetry, locale: locale)
            }
        }
    }

    private func submitCreate() async {
        createInputError = nil
        guard normalizedHouseholdName.isEmpty == false else {
            createInputError = AppLocalized.string(L10n.Family.pleaseEnterAGroupName, locale: locale)
            return
        }
        guard appRouter.canCreateOrJoinAnotherHousehold(
            fallbackJoinedCount: viewModel.joinedHouseholds.count
        ) else {
            appRouter.presentPremiumUpgrade()
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
        AnalyticsManager.logOnboardingStep(AnalyticsManager.OnboardingStep.createGroup)
        showCreateSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdId)
        appRouter.goToActiveMember()
        await appRouter.refreshStateFromBackend()
        await viewModel.fetchMyHouseholds(appRouter: appRouter)
    }

    private func submitJoin() async {
        joinInputError = nil
        guard isInviteCodeValid else {
            joinInputError = L10n.Family.invalidInviteCodeFormatMustBe6LettersOr.string()
            return
        }
        guard appRouter.canCreateOrJoinAnotherHousehold(
            fallbackJoinedCount: viewModel.joinedHouseholds.count
        ) else {
            appRouter.presentPremiumUpgrade()
            return
        }
        guard isJoiningFullScreenLoading == false else { return }
        isJoiningFullScreenLoading = true
        defer { isJoiningFullScreenLoading = false }

        let success = await viewModel.joinHousehold(inviteCode: normalizedInviteCode)
        guard success else { return }
        showJoinSheet = false
        AnalyticsManager.logOnboardingStep(AnalyticsManager.OnboardingStep.joinGroup)
        await appRouter.refreshStateFromBackend()
        await viewModel.fetchMyHouseholds(appRouter: appRouter)
        if let groupId = appRouter.selectedHouseholdId {
            AnalyticsManager.log(event: .groupJoined(groupId: groupId))
            AnalyticsManager.logInviteAccepted(householdId: groupId)
        } else if let joinedId = viewModel.joinedHouseholds.first?.householdId {
            AnalyticsManager.log(event: .groupJoined(groupId: joinedId))
            AnalyticsManager.logInviteAccepted(householdId: joinedId)
        }
    }
}

// MARK: - Card

struct JoinedHouseholdCard: View {
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
    @Binding var householdDescription: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(AppLocalized.string(L10n.Family.pleaseEnterAGroupName2, locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                TextField(AppLocalized.string(L10n.Common.forExampleWangGroupCourtyard, locale: locale), text: $householdName)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(AppLocalized.string(L10n.Family.groupDescriptionOptional, locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                TextField(
                    AppLocalized.string(L10n.Family.enterGroupDescriptionOptional, locale: locale),
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
                        Text(AppLocalized.string(L10n.Common.confirmCreation, locale: locale))
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
            .navigationTitle(AppLocalized.string(L10n.Family.createGroup, locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized.string(L10n.Common.close, locale: locale)) { dismiss() }
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
                        Text(AppLocalized.string(L10n.Common.scanToJoin, locale: locale))
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
                    Text(AppLocalized.string(L10n.Common.or, locale: locale))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(height: 1)
                }

                TextField(AppLocalized.string(L10n.Family.enterThe6DigitInvitationCode, locale: locale), text: $inviteCode)
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
                    Label(AppLocalized.string(L10n.Family.recognizingTheInvitationCodeInThePicture, locale: locale), systemImage: "photo")
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
                        Text(AppLocalized.string(L10n.Common.confirmToJoin, locale: locale))
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
            .navigationTitle(AppLocalized.string(L10n.Family.joinGroup, locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLocalized.string(L10n.Common.close, locale: locale)) { dismiss() }
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
            onError(AppLocalized.string(L10n.Common.cameraScanUnavailable, locale: .current))
            return UIViewController()
        }
        guard DataScannerViewController.isAvailable else {
            onError(AppLocalized.string(L10n.Common.cameraUnavailableCheckPermission, locale: .current))
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
            onError(L10n.Common.couldNotStartScannerPleaseTryAgainLater.string())
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
