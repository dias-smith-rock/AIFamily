import SwiftUI
import VisionKit
import Vision

// MARK: - Shared data

private enum OrganizationSwitcherData {
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
                name: name.isEmpty ? "未命名组织" : name
            )
        ]
    }

    static func currentName(for appRouter: AppRouter) -> String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未命名组织" : trimmed
    }
}

// MARK: - Task Tab：标题 + chevron 一体

/// 任务 Tab 顶栏：组织切换触发器 + 系统操作表。
struct OrganizationSwitcherControl: View {
    enum LabelStyle {
        case compact
        case prominent
    }

    @EnvironmentObject private var appRouter: AppRouter

    @Binding var isShowingCreateOrganization: Bool
    var labelStyle: LabelStyle = .compact
    @State private var isShowingSwitcher = false

    private var organizations: [AppRouter.HouseholdOption] {
        OrganizationSwitcherData.organizations(for: appRouter)
    }

    private var currentOrganizationName: String {
        OrganizationSwitcherData.currentName(for: appRouter)
    }

    var body: some View {
        Button {
            isShowingSwitcher = true
        } label: {
            HStack(spacing: 4) {
                Text(currentOrganizationName)
                    .font(labelStyle == .prominent ? .headline : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(labelStyle == .prominent ? 2 : 1)
                    .multilineTextAlignment(.leading)

                Image(systemName: "chevron.down")
                    .font(labelStyle == .prominent ? .caption : .caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .organizationSwitcherDialog(
            isPresented: $isShowingSwitcher,
            isShowingCreateOrganization: $isShowingCreateOrganization,
            organizations: organizations,
            selectedHouseholdId: appRouter.selectedHouseholdId,
            onSelect: { appRouter.chooseHousehold($0) }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Organization, \(currentOrganizationName), menu")
    }
}

// MARK: - 家庭 Tab：右侧独立 chevron

struct OrganizationSwitcherChevronButton: View {
    @EnvironmentObject private var appRouter: AppRouter

    @Binding var isShowingCreateOrganization: Bool
    @State private var isShowingSwitcher = false

    private var organizations: [AppRouter.HouseholdOption] {
        OrganizationSwitcherData.organizations(for: appRouter)
    }

    var body: some View {
        Button {
            isShowingSwitcher = true
        } label: {
            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .organizationSwitcherDialog(
            isPresented: $isShowingSwitcher,
            isShowingCreateOrganization: $isShowingCreateOrganization,
            organizations: organizations,
            selectedHouseholdId: appRouter.selectedHouseholdId,
            onSelect: { appRouter.chooseHousehold($0) }
        )
        .accessibilityLabel("切换组织")
    }
}

// MARK: - 组织切换操作表

private extension View {
    func organizationSwitcherDialog(
        isPresented: Binding<Bool>,
        isShowingCreateOrganization: Binding<Bool>,
        organizations: [AppRouter.HouseholdOption],
        selectedHouseholdId: UUID?,
        onSelect: @escaping (AppRouter.HouseholdOption) -> Void
    ) -> some View {
        modifier(
            OrganizationSwitcherDialogModifier(
                isPresented: isPresented,
                isShowingCreateOrganization: isShowingCreateOrganization,
                organizations: organizations,
                selectedHouseholdId: selectedHouseholdId,
                onSelect: onSelect
            )
        )
    }
}

private struct OrganizationSwitcherDialogModifier: ViewModifier {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter

    @Binding var isPresented: Bool
    @Binding var isShowingCreateOrganization: Bool
    let organizations: [AppRouter.HouseholdOption]
    let selectedHouseholdId: UUID?
    let onSelect: (AppRouter.HouseholdOption) -> Void

    @StateObject private var orgRoutingViewModel = AppViewModels.makeOrgRoutingViewModel()
    @State private var showJoinGroupSheet = false
    @State private var joinCode = ""
    @State private var joinInputError: String?
    @State private var showJoinScanner = false

    private var normalizedInviteCode: String {
        joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private var isInviteCodeValid: Bool {
        normalizedInviteCode.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("切换组织", isPresented: $isPresented, titleVisibility: .visible) {
                ForEach(organizations) { organization in
                    Button(organizationSwitcherOptionTitle(organization, isSelected: organization.id == selectedHouseholdId)) {
                        onSelect(organization)
                    }
                }
                Button("创建新组织") {
                    isShowingCreateOrganization = true
                }
                Button {
                    joinInputError = nil
                    showJoinGroupSheet = true
                } label: {
                    Label("加入已有群组", systemImage: "person.badge.plus")
                }
                Button("取消", role: .cancel) { }
            }
            .sheet(isPresented: $showJoinGroupSheet) {
                JoinExistingGroupSheet(
                    inviteCode: $joinCode,
                    inputError: $joinInputError,
                    isSubmitting: orgRoutingViewModel.isJoining,
                    onScan: {
                        showJoinScanner = true
                    },
                    onSubmit: {
                        await submitJoinGroup()
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showJoinScanner) {
                OrganizationJoinQRScannerSheet { raw in
                    if let code = firstInviteCode(from: raw.uppercased()) {
                        joinCode = code
                        joinInputError = nil
                    } else {
                        joinInputError = AppLocalized.string("未识别到有效邀请码，请重试。", locale: locale)
                    }
                    showJoinScanner = false
                } onError: { message in
                    joinInputError = message
                    showJoinScanner = false
                }
            }
    }

    private func firstInviteCode(from text: String) -> String? {
        let pattern = "\\b[A-Z0-9]{6}\\b"
        guard let range = text.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        return String(text[range])
    }

    private func submitJoinGroup() async {
        joinInputError = nil
        guard isInviteCodeValid else {
            joinInputError = String(localized: "邀请码格式无效：必须为 6 位字母或数字。")
            return
        }
        let success = await orgRoutingViewModel.joinGroup(code: normalizedInviteCode)
        guard success else {
            joinInputError = orgRoutingViewModel.errorMessage
            return
        }
        showJoinGroupSheet = false
        await appRouter.refreshStateFromBackend()
    }
}

private struct JoinExistingGroupSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    @Binding var inviteCode: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let onScan: () -> Void
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                TextField(AppLocalized.string("输入 6 位邀请码", locale: locale), text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Button {
                    onScan()
                } label: {
                    Label("相机扫码", systemImage: "qrcode.viewfinder")
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
                        Text("确认加入")
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
            .navigationTitle("加入已有群组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }
}

private struct OrganizationJoinQRScannerSheet: UIViewControllerRepresentable {
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

private func organizationSwitcherOptionTitle(_ organization: AppRouter.HouseholdOption, isSelected: Bool) -> String {
    guard isSelected else { return organization.name }
    return "\(organization.name) ✓"
}

// MARK: - Create Organization Sheet

struct CreateOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var organizationName: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("输入组织名称…", text: $organizationName)
                        .textInputAutocapitalization(.words)
                        .disabled(isSubmitting)
                } footer: {
                    if let inputError {
                        Text(inputError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("创建组织")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("创建") {
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
