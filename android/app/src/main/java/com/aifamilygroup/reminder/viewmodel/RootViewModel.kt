package com.aifamilygroup.reminder.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifamilygroup.reminder.data.auth.AuthRepository
import com.aifamilygroup.reminder.data.billing.BillingRepository
import com.aifamilygroup.reminder.data.push.PushRegistrar
import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.domain.model.AppRouteState
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class RootViewModel @Inject constructor(
    private val authRepository: AuthRepository,
    private val session: AppSession,
    private val billingRepository: BillingRepository,
    private val pushRegistrar: PushRegistrar,
) : ViewModel() {

    val routeState: StateFlow<AppRouteState> = session.routeState
        .stateIn(viewModelScope, SharingStarted.Eagerly, AppRouteState.Bootstrapping)

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

    fun signInGuest(onError: (String) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.signInAnonymously() }
                .onFailure { onError(it.message ?: "Guest sign-in failed") }
        }
    }

    fun signOut() {
        viewModelScope.launch { authRepository.signOut() }
    }

    fun createGroup(name: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.createHousehold(name) }
                .onFailure { onError(it.message ?: "Create group failed") }
        }
    }

    fun joinGroup(code: String, onError: (String) -> Unit) {
        viewModelScope.launch {
            runCatching { authRepository.joinHousehold(code) }
                .onFailure { onError(it.message ?: "Join failed") }
        }
    }
}
