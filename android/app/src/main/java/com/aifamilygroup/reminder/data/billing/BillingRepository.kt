package com.aifamilygroup.reminder.data.billing

import android.app.Activity
import android.content.Context
import com.android.billingclient.api.AcknowledgePurchaseParams
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingFlowParams
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.ProductDetails
import com.android.billingclient.api.Purchase
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.QueryProductDetailsParams
import com.android.billingclient.api.QueryPurchasesParams
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume

/**
 * Play Billing bridge. Entitlement sync to Supabase mirrors iOS RevenueCat path
 * (user_entitlements); wire webhook / client RPC in a follow-up once Play product IDs are final.
 */
@Singleton
class BillingRepository @Inject constructor(
    @ApplicationContext private val context: Context,
) : PurchasesUpdatedListener {

    private val _hasPremium = MutableStateFlow(false)
    val hasPremium: StateFlow<Boolean> = _hasPremium.asStateFlow()

    private val _productDetails = MutableStateFlow<List<ProductDetails>>(emptyList())
    val productDetails: StateFlow<List<ProductDetails>> = _productDetails.asStateFlow()

    private val _lastError = MutableStateFlow<String?>(null)
    val lastError: StateFlow<String?> = _lastError.asStateFlow()

    private val billingClient: BillingClient = BillingClient.newBuilder(context)
        .setListener(this)
        .enablePendingPurchases(
            PendingPurchasesParams.newBuilder().enableOneTimeProducts().build()
        )
        .build()

    fun startConnection() {
        if (billingClient.isReady) return
        billingClient.startConnection(object : BillingClientStateListener {
            override fun onBillingSetupFinished(result: BillingResult) {
                if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                    queryProducts()
                    queryActivePurchases()
                } else {
                    _lastError.value = result.debugMessage
                }
            }

            override fun onBillingServiceDisconnected() = Unit
        })
    }

    private fun queryProducts() {
        val productList = listOf(
            QueryProductDetailsParams.Product.newBuilder()
                .setProductId(PRO_MONTHLY_PRODUCT_ID)
                .setProductType(BillingClient.ProductType.SUBS)
                .build()
        )
        val params = QueryProductDetailsParams.newBuilder().setProductList(productList).build()
        billingClient.queryProductDetailsAsync(params) { result, productDetailsList ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                // Billing 6/7 callback second arg is List<ProductDetails>
                @Suppress("UNCHECKED_CAST")
                val list = productDetailsList as? List<ProductDetails> ?: emptyList()
                _productDetails.value = list
            }
        }
    }

    fun queryActivePurchases() {
        val params = QueryPurchasesParams.newBuilder()
            .setProductType(BillingClient.ProductType.SUBS)
            .build()
        billingClient.queryPurchasesAsync(params) { result, purchases ->
            if (result.responseCode == BillingClient.BillingResponseCode.OK) {
                _hasPremium.value = purchases.any { it.purchaseState == Purchase.PurchaseState.PURCHASED }
                purchases.filter { it.purchaseState == Purchase.PurchaseState.PURCHASED && !it.isAcknowledged }
                    .forEach { acknowledge(it) }
            }
        }
    }

    fun launchPurchase(activity: Activity, details: ProductDetails) {
        val offerToken = details.subscriptionOfferDetails?.firstOrNull()?.offerToken ?: return
        val productParams = BillingFlowParams.ProductDetailsParams.newBuilder()
            .setProductDetails(details)
            .setOfferToken(offerToken)
            .build()
        val flowParams = BillingFlowParams.newBuilder()
            .setProductDetailsParamsList(listOf(productParams))
            .build()
        billingClient.launchBillingFlow(activity, flowParams)
    }

    private fun acknowledge(purchase: Purchase) {
        val params = AcknowledgePurchaseParams.newBuilder()
            .setPurchaseToken(purchase.purchaseToken)
            .build()
        billingClient.acknowledgePurchase(params) { }
    }

    override fun onPurchasesUpdated(result: BillingResult, purchases: MutableList<Purchase>?) {
        if (result.responseCode == BillingClient.BillingResponseCode.OK && purchases != null) {
            _hasPremium.value = purchases.any { it.purchaseState == Purchase.PurchaseState.PURCHASED }
            purchases.forEach { if (!it.isAcknowledged) acknowledge(it) }
        } else if (result.responseCode != BillingClient.BillingResponseCode.USER_CANCELED) {
            _lastError.value = result.debugMessage
        }
    }

    suspend fun restore(): Boolean = suspendCancellableCoroutine { cont ->
        queryActivePurchases()
        cont.resume(_hasPremium.value)
    }

    companion object {
        /** Replace with Play Console subscription product id. */
        const val PRO_MONTHLY_PRODUCT_ID = "family_link_pro_monthly"
    }
}
