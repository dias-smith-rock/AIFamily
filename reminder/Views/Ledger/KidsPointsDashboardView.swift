import SwiftUI

struct KidsPointsDashboardView: View {
    @ObservedObject var viewModel: FamilyLedgerViewModel
    let canManageHousehold: Bool

    @State private var isShowingManualEntry = false
    @State private var showInsufficientPointsAlert = false

    var body: some View {
        VStack(spacing: 0) {
            pointsHeader
                .padding(.horizontal, 16)
                .padding(.top, 12)

            actionCapsules
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.pointsEntries.isEmpty {
                ContentUnavailableView {
                    Label(L10n.Ledger.noPointsEntries.localized, systemImage: "star")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.pointsEntries) { entry in
                        LedgerPointsRow(entry: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .sheet(isPresented: $isShowingManualEntry) {
            ManualPointsEntrySheet(
                viewModel: viewModel,
                canManageHousehold: canManageHousehold,
                onInsufficientPoints: { showInsufficientPointsAlert = true }
            )
        }
        .alert(L10n.Ledger.insufficientPointsTitle.localized, isPresented: $showInsufficientPointsAlert) {
            Button(L10n.Common.ok) {}
        } message: {
            Text(L10n.Ledger.insufficientPointsMessage.localized)
        }
    }

    @ViewBuilder
    private var pointsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            if canManageHousehold, viewModel.selectableChildProfiles.count > 1 {
                Picker(
                    L10n.Ledger.selectChildProfile.localized,
                    selection: profileSelectionBinding
                ) {
                    ForEach(viewModel.selectableChildProfiles) { profile in
                        Text(profile.displayName).tag(profile.id)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text(L10n.Ledger.pointsBalance.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let profileId = viewModel.selectedPointsProfileId {
                    Text("\(viewModel.pointsBalance(for: profileId))")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var profileSelectionBinding: Binding<UUID> {
        Binding(
            get: { viewModel.selectedPointsProfileId ?? viewModel.selectableChildProfiles.first?.id ?? UUID() },
            set: { viewModel.selectPointsProfile($0) }
        )
    }

    private var actionCapsules: some View {
        HStack(spacing: 10) {
            LedgerPointsActionCapsule(
                title: L10n.Ledger.voiceEntry.localized,
                systemImage: "mic",
                isEnabled: false
            ) {}

            LedgerPointsActionCapsule(
                title: L10n.Ledger.manualEntry.localized,
                systemImage: "square.and.pencil",
                isEnabled: viewModel.selectedPointsProfileId != nil
            ) {
                isShowingManualEntry = true
            }
        }
    }
}

private struct LedgerPointsRow: View {
    let entry: PointsLedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.description)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(signedPointsText)
                .font(.body.weight(.semibold))
                .foregroundStyle(entry.amount >= 0 ? .green : .orange)
        }
        .padding(.vertical, 4)
    }

    private var signedPointsText: String {
        entry.amount >= 0 ? "+\(entry.amount)" : "\(entry.amount)"
    }
}

private struct LedgerPointsActionCapsule: View {
    let title: LocalizedStringResource
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isEnabled == false)
        .opacity(isEnabled ? 1 : 0.45)
    }
}
