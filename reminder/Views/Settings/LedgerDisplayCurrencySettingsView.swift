import SwiftUI

struct LedgerDisplayCurrencySettingsView: View {
    @EnvironmentObject private var appSettings: AppSettingsManager

    var body: some View {
        List {
            Section {
                ForEach(LedgerCurrency.allCases) { currency in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            appSettings.ledgerDisplayCurrency = currency.code
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(currency.code)
                                    .foregroundStyle(.primary)
                                Text(currency.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if appSettings.ledgerDisplayCurrency == currency.code {
                                Image(systemName: "checkmark")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.tint)
                                    .transition(.opacity.combined(with: .scale))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text(L10n.Settings.ledgerDisplayCurrencyFooter.localized)
            }
        }
        .navigationTitle(L10n.Settings.ledgerDisplayCurrency.localized)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LedgerDisplayCurrencySettingsView()
            .environmentObject(AppSettingsManager.shared)
    }
}
