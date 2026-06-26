import SwiftUI
import VisionKit
import Vision

// MARK: - Shared data

enum GroupSwitcherData {
    static func organizations(for appRouter: AppRouter) -> [AppRouter.HouseholdOption] {
        let source = appRouter.recentHouseholds.isEmpty == false
            ? appRouter.recentHouseholds
            : appRouter.selectableHouseholds

        if source.isEmpty == false {
            return source
        }

        guard
            let householdId = appRouter.selectedHouseholdId,
            let membershipId = appRouter.selectedMembershipId
        else {
            return []
        }

        let name = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return [
            AppRouter.HouseholdOption(
                id: householdId,
                membershipId: membershipId,
                profileId: appRouter.selectedProfileId,
                name: name.isEmpty ? AppLocalized.localizedSync(L10n.Family.unnamedGroup) : StoredDisplayNameResolver.householdName(name),
                creatorHasActivePro: appRouter.selectedHouseholdCreatorHasActivePro,
                description: appRouter.selectedHouseholdDescription
            )
        ]
    }

    static func currentName(for appRouter: AppRouter) -> String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty { return AppLocalized.localizedSync(L10n.Family.unnamedGroup) }
        return StoredDisplayNameResolver.householdName(trimmed)
    }
}

// MARK: - Shared toolbar controls

struct GroupSwitcherToolbarButton: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var groupSwitcher: GroupSwitcherCoordinator

    var body: some View {
        Button {
            groupSwitcher.showSwitchGroupDialog = true
        } label: {
            HStack(spacing: 4) {
                Text(GroupSwitcherData.currentName(for: appRouter))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel(L10n.Family.group.formatted(locale: locale, GroupSwitcherData.currentName(for: appRouter)))
    }
}

struct AccentPlusToolbarButton: View {
    let accessibilityLabel: L10n.Entry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

// MARK: - 切换群组半屏 Sheet

struct SwitchGroupSheetView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject var coordinator: GroupSwitcherCoordinator

    private var organizations: [AppRouter.HouseholdOption] {
        GroupSwitcherData.organizations(for: appRouter)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.Family.switchGroup.localized)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(organizations) { organization in
                        Button {
                            appRouter.chooseHousehold(organization)
                            coordinator.showSwitchGroupDialog = false
                        } label: {
                            HStack {
                                Text(organization.name)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                if organization.id == appRouter.selectedHouseholdId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if organization.id != organizations.last?.id {
                            Divider()
                                .padding(.horizontal, 20)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    coordinator.presentCreateOrganizationAfterDismiss(appRouter: appRouter)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text(L10n.Family.createNewGroup2.localized)
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.presentJoinGroupAfterDismiss(appRouter: appRouter)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                        Text(L10n.Family.joinAGroup.localized)
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .background(Color(.systemBackground))
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Create Organization Sheet

struct CreateOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding var organizationName: String
    @Binding var organizationDescription: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField(AppLocalized.string(L10n.Family.enterGroupName, locale: locale), text: $organizationName)
                        .textInputAutocapitalization(.words)
                        .disabled(isSubmitting)
                        .createGroupFieldStyle()

                    TextField(AppLocalized.string(L10n.Family.enterGroupDescriptionOptional, locale: locale), text: $organizationDescription, axis: .vertical)
                        .lineLimit(3 ... 6)
                        .disabled(isSubmitting)
                        .createGroupFieldStyle()

                    if let inputError {
                        Text(inputError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .navigationTitle(L10n.Family.createGroup.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(L10n.Common.create) {
                            Task { await onSubmit() }
                        }
                        .disabled(
                            organizationName
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                }
            }
        }
    }
}

private extension View {
    func createGroupFieldStyle() -> some View {
        textFieldStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Join group sheet + scanner

struct JoinExistingGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding var inviteCode: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let parseInviteCode: (String) -> String?
    let onSubmit: () async -> Void

    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField(AppLocalized.string(L10n.Family.enterThe6DigitInvitationCode, locale: locale), text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    showScanner = true
                } label: {
                    Label(L10n.Common.cameraScanCode.localized, systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

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
                        Text(L10n.Common.confirmToJoin.localized)
                            .font(.system(size: 17, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSubmitting)

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(L10n.Family.joinAGroup.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                        .disabled(isSubmitting)
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                OrganizationJoinQRScannerContainer { raw in
                    if let code = parseInviteCode(raw.uppercased()) {
                        inviteCode = code
                        inputError = nil
                    } else {
                        inputError = AppLocalized.string(
                            L10n.Family.noValidInviteCodeDetected,
                            locale: locale
                        )
                    }
                    showScanner = false
                } onError: { message in
                    inputError = message
                    showScanner = false
                }
                .environment(\.locale, locale)
            }
        }
    }
}

struct OrganizationJoinQRScannerContainer: View {
    @Environment(\.dismiss) private var dismiss

    let onCode: (String) -> Void
    let onError: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            OrganizationJoinQRScannerSheet(onCode: onCode, onError: onError)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 12)
            .padding(.leading, 16)
            .accessibilityLabel(Text(L10n.Common.close.localized))
        }
    }
}

struct OrganizationJoinQRScannerSheet: UIViewControllerRepresentable {
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
