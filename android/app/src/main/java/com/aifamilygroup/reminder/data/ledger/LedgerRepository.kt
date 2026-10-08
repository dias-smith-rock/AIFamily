package com.aifamilygroup.reminder.data.ledger

import com.aifamilygroup.reminder.domain.model.LedgerTransaction
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LedgerRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetchRecent(householdId: String, limit: Int = 50): List<LedgerTransaction> {
        return client.from("ledger_transactions")
            .select {
                filter { eq("household_id", householdId) }
            }
            .decodeList<LedgerTransaction>()
            .take(limit)
    }
}
