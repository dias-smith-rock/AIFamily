import SwiftUI

struct HouseholdPickerView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                header
                optionsList
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(.systemGroupedBackground))
            .navigationBarHidden(true)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalized.string(L10n.Family.selectGroup, locale: locale))
                .font(.system(size: 32, weight: .bold))
            Text(AppLocalized.string(L10n.Family.itIsDetectedThatYouHaveJoinedMultipleGro, locale: locale))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var optionsList: some View {
        if appRouter.selectableHouseholds.isEmpty {
            ProgressView(AppLocalized.string(L10n.Family.loadingGroupList, locale: locale))
                .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            VStack(spacing: 10) {
                ForEach(appRouter.selectableHouseholds) { option in
                    Button {
                        appRouter.chooseHousehold(option)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(option.name)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Text(option.id.uuidString)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    HouseholdPickerView()
        .environmentObject(AppRouter())
}
