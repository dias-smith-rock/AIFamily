package com.aifamilygroup.reminder.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifamilygroup.reminder.data.ledger.LedgerRepository
import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.domain.model.LedgerTransaction
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class WalletViewModel @Inject constructor(
    private val ledgerRepository: LedgerRepository,
    private val session: AppSession,
) : ViewModel() {
    private val _transactions = MutableStateFlow<List<LedgerTransaction>>(emptyList())
    val transactions: StateFlow<List<LedgerTransaction>> = _transactions.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    init {
        viewModelScope.launch {
            session.selectedHouseholdId.collectLatest { id ->
                if (id != null) reload()
            }
        }
    }

    fun reload() {
        val householdId = session.selectedHouseholdId.value ?: return
        viewModelScope.launch {
            runCatching { ledgerRepository.fetchRecent(householdId) }
                .onSuccess { _transactions.value = it }
                .onFailure { _error.value = it.message }
        }
    }
}
