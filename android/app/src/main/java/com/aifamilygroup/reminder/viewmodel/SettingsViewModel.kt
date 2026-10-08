package com.aifamilygroup.reminder.viewmodel

import android.app.Activity
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifamilygroup.reminder.data.billing.BillingRepository
import com.android.billingclient.api.ProductDetails
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val billingRepository: BillingRepository,
) : ViewModel() {
    val hasPremium: StateFlow<Boolean> = billingRepository.hasPremium
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    val products: StateFlow<List<ProductDetails>> = billingRepository.productDetails
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val billingError: StateFlow<String?> = billingRepository.lastError
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun refreshBilling() {
        billingRepository.startConnection()
        billingRepository.queryActivePurchases()
    }

    fun purchase(activity: Activity, details: ProductDetails) {
        billingRepository.launchPurchase(activity, details)
    }

    fun restore() {
        viewModelScope.launch { billingRepository.restore() }
    }
}
