import SwiftUI

// MARK: - Ledger

extension L10n {
    enum Ledger {
        static let wallet = Entry(key: "ledger_wallet", table: .ledger)
        static let familyExpense = Entry(key: "ledger_family_expense", table: .ledger)
        static let behaviorPoints = Entry(key: "ledger_behavior_points", table: .ledger)
        static let manualEntry = Entry(key: "ledger_manual_entry", table: .ledger)
        static let aiReceipt = Entry(key: "ledger_ai_receipt", table: .ledger)
        static let voiceEntry = Entry(key: "ledger_voice_entry", table: .ledger)
        static let expense = Entry(key: "ledger_expense", table: .ledger)
        static let income = Entry(key: "ledger_income", table: .ledger)
        static let addPoints = Entry(key: "ledger_add_points", table: .ledger)
        static let redeem = Entry(key: "ledger_redeem", table: .ledger)
        static let monthlyExpense = Entry(key: "ledger_monthly_expense", table: .ledger)
        static let monthlyIncome = Entry(key: "ledger_monthly_income", table: .ledger)
        static let monthlyNet = Entry(key: "ledger_monthly_net", table: .ledger)
        static let noExpenseEntries = Entry(key: "ledger_no_expense_entries", table: .ledger)
        static let noPointsEntries = Entry(key: "ledger_no_points_entries", table: .ledger)
        static let pointsBalance = Entry(key: "ledger_points_balance", table: .ledger)
        static let selectChildProfile = Entry(key: "ledger_select_child_profile", table: .ledger)
        static let amount = Entry(key: "ledger_amount", table: .ledger)
        static let category = Entry(key: "ledger_category", table: .ledger)
        static let payer = Entry(key: "ledger_payer", table: .ledger)
        static let note = Entry(key: "ledger_note", table: .ledger)
        static let titleField = Entry(key: "ledger_title_field", table: .ledger)
        static let points = Entry(key: "ledger_points", table: .ledger)
        static let descriptionField = Entry(key: "ledger_description_field", table: .ledger)
        static let insufficientPointsTitle = Entry(key: "ledger_insufficient_points_title", table: .ledger)
        static let insufficientPointsMessage = Entry(key: "ledger_insufficient_points_message", table: .ledger)
        static let defaultEarnNote = Entry(key: "ledger_default_earn_note", table: .ledger)
        static let defaultRedemptionNote = Entry(key: "ledger_default_redemption_note", table: .ledger)
        static let proFeature = Entry(key: "ledger_pro_feature", table: .ledger)
        static let saveEntry = Entry(key: "ledger_save_entry", table: .ledger)
    }
}
