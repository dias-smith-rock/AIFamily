import SwiftUI

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
        confirmationDialog("切换组织", isPresented: isPresented, titleVisibility: .visible) {
            ForEach(organizations) { organization in
                Button(organizationSwitcherOptionTitle(organization, isSelected: organization.id == selectedHouseholdId)) {
                    onSelect(organization)
                }
            }
            Button("创建新组织") {
                isShowingCreateOrganization.wrappedValue = true
            }
            Button("取消", role: .cancel) { }
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
