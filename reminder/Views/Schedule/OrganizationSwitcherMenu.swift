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
                name: name.isEmpty ? "未命名群组" : name,
                isPremium: appRouter.selectedHouseholdIsPremium,
                description: appRouter.selectedHouseholdDescription
            )
        ]
    }

    static func currentName(for appRouter: AppRouter) -> String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "未命名群组" : trimmed
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
        VStack(alignment: .leading, spacing: 0) {
            Text("切换群组")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                            .padding()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if organization.id != organizations.last?.id {
                            Divider()
                                .padding(.horizontal)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    coordinator.presentCreateOrganizationAfterDismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "plus.circle.fill")
                        Text("新建群组")
                    }
                    .foregroundStyle(.blue)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.presentJoinGroupAfterDismiss()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.plus")
                        Text("加入已有群组")
                    }
                    .foregroundStyle(.blue)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - Create Organization Sheet

struct CreateOrganizationSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var organizationName: String
    @Binding var organizationDescription: String
    @Binding var inputError: String?
    let isSubmitting: Bool
    let onSubmit: () async -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    TextField("输入群组名称…", text: $organizationName)
                        .textInputAutocapitalization(.words)
                        .disabled(isSubmitting)
                        .createGroupFieldStyle()

                    TextField("输入群组描述（选填）…", text: $organizationDescription, axis: .vertical)
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
            .navigationTitle("创建群组")
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

struct OrganizationJoinQRScannerSheet: UIViewControllerRepresentable {
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
