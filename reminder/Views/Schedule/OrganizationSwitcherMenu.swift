import SwiftUI
import VisionKit
import Vision

// MARK: - Shared data

enum GroupSwitcherData {
    static func organizations(for appRouter: AppRouter) -> [AppRouter.HouseholdOption] {
        if appRouter.selectableHouseholds.isEmpty == false {
            return appRouter.selectableHouseholds
        }

        let source = appRouter.recentHouseholds
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

    /// Schedule / Todo 用多选；Wallet 用单选活动组织。
    var presentationMode: GroupSwitcherCoordinator.PresentationMode = .multiView

    private var selectedCount: Int {
        max(appRouter.selectedHouseholdIds.count, appRouter.selectedHouseholdId == nil ? 0 : 1)
    }

    var body: some View {
        Button {
            groupSwitcher.present(mode: presentationMode)
        } label: {
            HStack(spacing: 6) {
                if let primaryId = appRouter.selectedHouseholdId {
                    HouseholdColorDot(householdId: primaryId, size: 7)
                }
                Text(GroupSwitcherData.currentName(for: appRouter))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if presentationMode == .multiView, selectedCount > 1 {
                    Text("\(selectedCount)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel(accessibilityTitle)
    }

    private var accessibilityTitle: String {
        let name = GroupSwitcherData.currentName(for: appRouter)
        if selectedCount > 1 {
            return L10n.Family.group.formatted(
                locale: locale,
                "\(name) · \(L10n.Family.viewingGroupsCount.formatted(locale: locale, selectedCount))"
            )
        }
        return L10n.Family.group.formatted(locale: locale, name)
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
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @ObservedObject var coordinator: GroupSwitcherCoordinator
    @State private var draftSelectedIds: Set<UUID> = []

    private var organizations: [AppRouter.HouseholdOption] {
        GroupSwitcherData.organizations(for: appRouter)
    }

    private var isMultiView: Bool {
        coordinator.presentationMode == .multiView
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(L10n.Common.cancel) {
                    coordinator.showSwitchGroupDialog = false
                }
                Spacer()
                Text(
                    isMultiView
                        ? L10n.Family.selectGroupsToView.localized
                        : L10n.Family.selectGroup.localized
                )
                    .font(.headline)
                Spacer()
                if isMultiView {
                    Button(L10n.Common.finish) {
                        applySelectionAndDismiss()
                    }
                    .disabled(draftSelectedIds.isEmpty)
                    .fontWeight(.semibold)
                } else {
                    // 与取消对称占位，保持标题居中
                    Color.clear
                        .frame(width: 44, height: 1)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)

            if isMultiView {
                Text(L10n.Family.multiSelectGroupsHint.localized)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(organizations) { organization in
                        if isMultiView {
                            multiViewRow(for: organization)
                        } else {
                            singleActiveRow(for: organization)
                        }

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
        .onAppear {
            let existing = Set(appRouter.selectedHouseholdIds)
            if existing.isEmpty, let current = appRouter.selectedHouseholdId {
                draftSelectedIds = [current]
            } else {
                draftSelectedIds = existing
            }
            HouseholdColorStore.ensureAssigned(ids: organizations.map(\.id))
        }
    }

    @ViewBuilder
    private func multiViewRow(for organization: AppRouter.HouseholdOption) -> some View {
        let isChecked = draftSelectedIds.contains(organization.id)
        let isActive = organization.id == appRouter.selectedHouseholdId
        HStack(spacing: 12) {
            Button {
                toggleSelection(organization.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChecked ? Color.accentColor : .secondary)
                    HouseholdColorDot(householdId: organization.id, size: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(organization.name)
                            .foregroundStyle(.primary)
                        if isActive {
                            Text(L10n.Family.activeWriteGroup.localized)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isChecked, isActive == false {
                Button {
                    appRouter.chooseHousehold(organization)
                } label: {
                    Text(L10n.Family.setAsActiveGroup.localized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func singleActiveRow(for organization: AppRouter.HouseholdOption) -> some View {
        let isActive = organization.id == appRouter.selectedHouseholdId
        return Button {
            appRouter.chooseHousehold(organization)
            coordinator.showSwitchGroupDialog = false
        } label: {
            HStack(spacing: 12) {
                HouseholdColorDot(householdId: organization.id, size: 10)
                Text(organization.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                if isActive {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private func toggleSelection(_ id: UUID) {
        if draftSelectedIds.contains(id) {
            guard draftSelectedIds.count > 1 else { return }
            draftSelectedIds.remove(id)
        } else {
            draftSelectedIds.insert(id)
        }
    }

    private func applySelectionAndDismiss() {
        let ordered = organizations.map(\.id).filter { draftSelectedIds.contains($0) }
        appRouter.setViewHouseholdIds(ordered)
        coordinator.showSwitchGroupDialog = false
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
