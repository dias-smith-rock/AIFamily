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
                name: name.isEmpty ? "Untitled Organization" : name
            )
        ]
    }

    static func currentName(for appRouter: AppRouter) -> String {
        let trimmed = appRouter.selectedHouseholdName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Untitled Organization" : trimmed
    }
}

// MARK: - Task Tab：标题 + chevron 一体

/// 任务 Tab 顶栏：组织切换触发器 + 下拉面板。
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
        .organizationSwitcherPopover(
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
        .organizationSwitcherPopover(
            isPresented: $isShowingSwitcher,
            isShowingCreateOrganization: $isShowingCreateOrganization,
            organizations: organizations,
            selectedHouseholdId: appRouter.selectedHouseholdId,
            onSelect: { appRouter.chooseHousehold($0) }
        )
        .accessibilityLabel("Switch organization")
    }
}

// MARK: - Popover attachment

private extension View {
    func organizationSwitcherPopover(
        isPresented: Binding<Bool>,
        isShowingCreateOrganization: Binding<Bool>,
        organizations: [AppRouter.HouseholdOption],
        selectedHouseholdId: UUID?,
        onSelect: @escaping (AppRouter.HouseholdOption) -> Void
    ) -> some View {
        popover(isPresented: isPresented, arrowEdge: .top) {
            OrganizationSwitcherPanel(
                organizations: organizations,
                selectedHouseholdId: selectedHouseholdId,
                onSelect: { option in
                    onSelect(option)
                    isPresented.wrappedValue = false
                },
                onCreate: {
                    isPresented.wrappedValue = false
                    isShowingCreateOrganization.wrappedValue = true
                }
            )
            .presentationCompactAdaptation(.popover)
        }
    }
}

// MARK: - Popover Panel

private struct OrganizationSwitcherPanel: View {
    let organizations: [AppRouter.HouseholdOption]
    let selectedHouseholdId: UUID?
    let onSelect: (AppRouter.HouseholdOption) -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if organizations.isEmpty == false {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(organizations) { organization in
                            Button {
                                onSelect(organization)
                            } label: {
                                organizationRow(for: organization)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Divider()

            Button(action: onCreate) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 36, alignment: .center)

                    Text("Create New Organization")
                        .font(.body)
                        .foregroundStyle(Color.accentColor)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .frame(minWidth: 300)
    }

    private func organizationRow(for organization: AppRouter.HouseholdOption) -> some View {
        HStack(spacing: 12) {
            OrganizationAvatarView(name: organization.name)

            Text(organization.name)
                .font(.body)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if organization.id == selectedHouseholdId {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// MARK: - Avatar

private struct OrganizationAvatarView: View {
    let name: String

    private var initials: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "O" }
        return String(trimmed.prefix(1)).uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.14))
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 36, height: 36)
    }
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
                    TextField("Enter organization name...", text: $organizationName)
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
            .navigationTitle("Create Organization")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Create") {
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
