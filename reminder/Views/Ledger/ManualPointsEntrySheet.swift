import SwiftUI

struct ManualPointsEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject var viewModel: FamilyLedgerViewModel
    let canManageHousehold: Bool
    let onInsufficientPoints: () -> Void

    @State private var isRedemption = false
    @State private var pointsText = ""
    @State private var descriptionText = ""
    @State private var selectedProfileId: UUID?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("", selection: $isRedemption) {
                        Text(L10n.Ledger.addPoints.localized).tag(false)
                        Text(L10n.Ledger.redeem.localized).tag(true)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }

                if canManageHousehold, viewModel.selectableChildProfiles.count > 1 {
                    Section {
                        Picker(L10n.Ledger.selectChildProfile.localized, selection: profileBinding) {
                            ForEach(viewModel.selectableChildProfiles) { profile in
                                Text(profile.displayName).tag(profile.id)
                            }
                        }
                    }
                }

                Section {
                    TextField(AppLocalized.string(L10n.Ledger.points, locale: locale), text: $pointsText)
                        .keyboardType(.numberPad)
                    TextField(AppLocalized.string(L10n.Ledger.descriptionField, locale: locale), text: $descriptionText, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(L10n.Ledger.manualEntry.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Ledger.saveEntry.localized) {
                        Task { await saveEntry() }
                    }
                    .disabled(canSave == false || isSaving)
                }
            }
            .onAppear {
                selectedProfileId = viewModel.selectedPointsProfileId ?? viewModel.selectableChildProfiles.first?.id
            }
        }
    }

    private var profileBinding: Binding<UUID> {
        Binding(
            get: { selectedProfileId ?? viewModel.selectableChildProfiles.first?.id ?? UUID() },
            set: { selectedProfileId = $0 }
        )
    }

    private var canSave: Bool {
        parsedPoints != nil && (parsedPoints ?? 0) > 0 && selectedProfileId != nil
    }

    private var parsedPoints: Int? {
        Int(pointsText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func saveEntry() async {
        guard let points = parsedPoints,
              let profileId = selectedProfileId ?? viewModel.selectedPointsProfileId else {
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await viewModel.createPointsEntry(
                isRedemption: isRedemption,
                points: points,
                description: descriptionText,
                targetProfileId: profileId
            )
            dismiss()
        } catch LedgerValidationError.insufficientPoints {
            onInsufficientPoints()
        } catch {
            // noop
        }
    }
}
