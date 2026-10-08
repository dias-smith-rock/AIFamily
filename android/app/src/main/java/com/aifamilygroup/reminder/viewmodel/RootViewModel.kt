package com.aifamilygroup.reminder.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifamilygroup.reminder.data.auth.AuthRepository
import com.aifamilygroup.reminder.data.billing.BillingRepository
import com.aifamilygroup.reminder.data.push.PushRegistrar
import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.domain.model.AppRouteState
import com.aifamilygroup.reminder.domain.model.JoinedHousehold
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

private const val AUTH_GOOGLE_TAG = "AuthGoogle"

@HiltViewModel
class RootViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val session: AppSession,
    private val billingRepository: BillingRepository,
    private val pushRegistrar: PushRegistrar,
) : ViewModel() {

    val routeState: StateFlow<AppRouteState> = session.routeState
        .stateIn(viewModelScope, SharingStarted.Eagerly, AppRouteState.Bootstrapping)

    val households: StateFlow<List<JoinedHousehold>> = session.households
        .stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    init {
        viewModelScope.launch {
            runCatching { authRepository.bootstrap() }
                .onFailure { session.setUnauthenticated() }
            billingRepository.startConnection()
            pushRegistrar.register()
        }
    }

    fun signInEmail(email: String, password: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.signInWithEmail(email, password) }
                .onFailure { onError(it.message ?: "Sign-in failed") }
        }
    }

    /** [onComplete] receives null on success, or an error message. */
    fun signInWithGoogleIdToken(idToken: String, onComplete: (String?) -> Unit) {
        viewModelScope.launch {
            Log.i(AUTH_GOOGLE_TAG, "viewModel step=begin_supabase idTokenLen=${idToken.length}")
            runCatching { authRepository.signInWithGoogleIdToken(idToken) }
                .onSuccess {
                    Log.i(AUTH_GOOGLE_TAG, "viewModel step=supabase_ok")
                    onComplete(null)
                }
                .onFailure {
                    Log.e(
                        AUTH_GOOGLE_TAG,
                        "viewModel step=supabase_error type=${it.javaClass.simpleName} message=${it.message}",
                        it,
                    )
                    onComplete(it.message ?: "Google sign-in failed")
                }
        }
    }

    /** [onComplete] receives null on success, or an error message. */
    fun signInGuest(onComplete: (String?) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.signInAnonymously() }
                .onSuccess { onComplete(null) }
                .onFailure { onComplete(it.message ?: "Guest sign-in failed") }
        }
    }

    fun signOut() {
        viewModelScope.launch { authRepository.signOut() }
    }

    fun selectHousehold(household: JoinedHousehold) {
        session.enterHousehold(household)
    }

    fun createGroup(name: String, onComplete: (String?) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.createHousehold(name) }
                .onSuccess { onComplete(null) }
                .onFailure { onComplete(it.message ?: "Create group failed") }
        }
    }

    fun joinGroup(code: String, onComplete: (String?) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.joinHousehold(code) }
                .onSuccess { onComplete(null) }
                .onFailure { onComplete(it.message ?: "Join failed") }
        }
    }

    fun refreshHouseholds(onComplete: (String?) -> Unit = {}) {
        viewModelScope.launch {
            runCatching { authRepository.refreshHouseholds() }
                .onSuccess { onComplete(null) }
                .onFailure { onComplete(it.message ?: "Refresh failed") }
        }
    }
}
