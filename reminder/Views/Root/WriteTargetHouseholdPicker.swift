import SwiftUI

/// 新建任务 / Todo / 记账前选择写入组织；默认最近活动组织。
struct WriteTargetHouseholdPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    let onConfirm: (AppRouter.HouseholdOption) -> Void

    @State private var selectedId: UUID?

    private var organizations: [AppRouter.HouseholdOption] {
        GroupSwitcherData.organizations(for: appRouter)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(organizations) { organization in
                    Button {
                        selectAndDismiss(organization)
                    } label: {
                        HStack(spacing: 12) {
                            HouseholdColorDot(householdId: organization.id, size: 10)
                            Text(organization.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if organization.id == selectedId {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.Family.selectGroup.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
            }
            .onAppear {
                selectedId = appRouter.selectedHouseholdId ?? organizations.first?.id
                HouseholdColorStore.ensureAssigned(ids: organizations.map(\.id))
            }
        }
    }

    private func selectAndDismiss(_ organization: AppRouter.HouseholdOption) {
        selectedId = organization.id
        appRouter.chooseHouseholdForWrite(organization)
        onConfirm(organization)
        dismiss()
    }
}
