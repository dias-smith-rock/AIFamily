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
    @State private var showGuestExitDialog = false
    @State private var showLinkAccountSheet = false
    @State private var showRegisteredSignOutAlert = false

    var body: some View {
        orgRoutingNavigationStack
            .onAppear {
                LoginFlowPerformanceTracing.mark("orgRoutingView.onAppear", appRouter: appRouter)
                appRouter.notifyOrgRoutingSurfaceDidAppear()
            }
            .task {
                await LoginFlowPerformanceTracing.measure(
                    "orgRoutingView.loadJoinedHouseholds",
                    appRouter: appRouter
                ) {
                    await loadJoinedHouseholdsForOrgRouting()
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
            .sheet(isPresented: $showCreateSheet) { createHouseholdSheet }
            .sheet(isPresented: $showJoinSheet) { joinHouseholdSheet }
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
                if isJoiningFullScreenLoading {
                    routingOverlay(message: L10n.Family.joiningGroup)
                } else if appRouter.isResolvingHouseholdRouting {
                    routingOverlay(message: L10n.Family.loadingYourGroups)
                }
            }
            .guestSessionExitDialogs(
                showGuestExitDialog: $showGuestExitDialog,
                showLinkAccountSheet: $showLinkAccountSheet,
                isProcessing: $isSigningOut,
                onError: { message in
                    localErrorMessage = message
                    showErrorAlert = true
                }
            )
            .alert(L10n.Auth.logOut, isPresented: $showRegisteredSignOutAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.quit, role: .destructive) {
                    Task { await performRegisteredSignOut() }
                }
            } message: {
                Text(L10n.Common.areYouSureYouWantToLogOutOfYourCurrent.localized)
            }
    }

    private var orgRoutingNavigationStack: some View {
        NavigationStack {
            orgRoutingScrollContent
                .background(AppTheme.ColorToken.background)
                .navigationTitle(AppLocalized.string(L10n.Common.welcomeToWesync, locale: locale))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            if appRouter.isAnonymousUser {
                                showGuestExitDialog = true
                            } else {
                                showRegisteredSignOutAlert = true
                            }
                        } label: {
                            if isSigningOut {
                                ProgressView()
                            } else {
                                Text(
                                    AppLocalized.string(
                                        appRouter.isAnonymousUser
                                            ? L10n.Auth.returnToLogin
                                            : L10n.Auth.logOut,
                                        locale: locale
                                    )
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isSigningOut)
                    }
                }
        }
    }

    private var orgRoutingScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                joinedHouseholdsSection

                Text(AppLocalized.string(L10n.Common.pleaseChooseAWayToContinue, locale: locale))
                    .font(AppTheme.FontToken.subtitle)
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)

                RouteActionCard(
                    icon: "house.fill",
                    title: AppLocalized.string(L10n.Family.createBrandNewGroupSpace, locale: locale),
                    backgroundColor: Color.orange.opacity(0.12)
                ) {
                    createInputError = nil
                    showCreateSheet = true
                }

                RouteActionCard(
                    icon: "qrcode.viewfinder",
                    title: AppLocalized.string(L10n.Family.joinViaScanOrInviteCode, locale: locale),
                    backgroundColor: Color.green.opacity(0.12)
                ) {
                    joinInputError = nil
                    showJoinSheet = true
                }
            }
            .padding(20)
        }
        .refreshable {
            await refreshHouseholdRouting()
        }
    }

    @ViewBuilder
    private var joinedHouseholdsSection: some View {
        if viewModel.joinedHouseholds.isEmpty {
            emptyJoinedHouseholdsPlaceholder
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalized.string(L10n.Family.myGroups, locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.ColorToken.textSecondary)

                ForEach(viewModel.joinedHouseholds) { joined in
                    JoinedHouseholdCard(joined: joined) {
                        appRouter.chooseJoinedHousehold(joined)
                    }
                }
            }
        }
    }

    private var emptyJoinedHouseholdsPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "house.and.flag")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            Text(AppLocalized.string(L10n.Family.youHavenTJoinedAnyGroupsYet, locale: locale))
                .font(.headline)
                .foregroundStyle(.primary)
            Text(AppLocalized.string(L10n.Family.createANewGroupOrJoinSomeoneElseSExisti, locale: locale))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func loadJoinedHouseholdsForOrgRouting() async {
        await viewModel.fetchMyHouseholds(appRouter: appRouter)
        #if DEBUG
        GuestSessionDiagnostics.log(
            "guest.orgRouting.loadFinished",
            appRouter: appRouter,
            note: "joinedCount=\(viewModel.joinedHouseholds.count) isLoading=\(viewModel.isLoading)"
        )
        #endif
        appRouter.notifyOrgRoutingHouseholdListLoadFinished()
    }

    private func refreshHouseholdRouting() async {
        guard appRouter.isResolvingHouseholdRouting == false else { return }
        await viewModel.fetchMyHouseholds(appRouter: appRouter)
    }

    private func routingOverlay(message: L10n.Entry) -> some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(AppLocalized.string(message, locale: locale))
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

    private var createHouseholdSheet: some View {
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

    private var joinHouseholdSheet: some View {
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
        showCreateSheet = false
        appRouter.preferHouseholdOnNextRefresh(createdId)
        appRouter.goToActiveMember()
        await appRouter.refreshStateFromBackend()
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
        await appRouter.refreshStateFromBackend()
        if let groupId = appRouter.selectedHouseholdId {
            AnalyticsManager.log(event: .groupJoined(groupId: groupId))
        }
    }

    private func performRegisteredSignOut() async {
        guard isSigningOut == false else { return }
        isSigningOut = true
        defer { isSigningOut = false }

        let succeeded = await viewModel.signOut(appRouter: appRouter)
        if succeeded == false, let message = viewModel.authErrorMessage {
            localErrorMessage = message
            showErrorAlert = true
        }
    }
}

private struct RouteActionCard: View {
    let icon: String
    let title: String
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

                Text(title)
                    .font(AppTheme.FontToken.section)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)

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
    OrgRoutingView()
        .environmentObject(AppRouter())
}
