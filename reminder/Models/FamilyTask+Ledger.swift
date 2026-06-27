import Foundation

extension FamilyTask {
    static let ledgerExpenseTaskType = "expense"
    static let ledgerIncomeTaskType = "income"

    var isLedgerExpenseEntry: Bool {
        taskType == Self.ledgerExpenseTaskType
    }

    var isLedgerIncomeEntry: Bool {
        taskType == Self.ledgerIncomeTaskType
    }

    var isLedgerEntry: Bool {
        isLedgerExpenseEntry || isLedgerIncomeEntry
    }

    /// 公账实付金额（`actual_amount`）；支出为正数展示，写入时带符号由 task_type 决定。
    var ledgerSignedAmount: Double {
        let magnitude = actualAmount ?? 0
        return isLedgerIncomeEntry ? magnitude : -abs(magnitude)
    }

    var ledgerAmountDisplayMagnitude: Double {
        abs(actualAmount ?? 0)
    }
}
