package com.aifamilygroup.reminder.data.session

import com.aifamilygroup.reminder.domain.model.AppRouteState
import com.aifamilygroup.reminder.domain.model.JoinedHousehold
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppSession @Inject constructor() {
    private val _routeState = MutableStateFlow(AppRouteState.Bootstrapping)
    val routeState: StateFlow<AppRouteState> = _routeState.asStateFlow()

    private val _households = MutableStateFlow<List<JoinedHousehold>>(emptyList())
    val households: StateFlow<List<JoinedHousehold>> = _households.asStateFlow()

    private val _selectedHouseholdId = MutableStateFlow<String?>(null)
    val selectedHouseholdId: StateFlow<String?> = _selectedHouseholdId.asStateFlow()

    private val _selectedMembershipId = MutableStateFlow<String?>(null)
    val selectedMembershipId: StateFlow<String?> = _selectedMembershipId.asStateFlow()

    private val _selectedProfileId = MutableStateFlow<String?>(null)
    val selectedProfileId: StateFlow<String?> = _selectedProfileId.asStateFlow()

    private val _userId = MutableStateFlow<String?>(null)
    val userId: StateFlow<String?> = _userId.asStateFlow()

    fun setUnauthenticated() {
        _userId.value = null
        _households.value = emptyList()
        _selectedHouseholdId.value = null
        _selectedMembershipId.value = null
        _selectedProfileId.value = null
        _routeState.value = AppRouteState.Unauthenticated
    }

    fun setUser(userId: String) {
        _userId.value = userId
    }

    fun applyHouseholds(list: List<JoinedHousehold>) {
        _households.value = list
        val hasActive = list.any { it.status.equals("active", ignoreCase = true) }
        val hasPending = list.any { it.status.equals("pending", ignoreCase = true) }
        when {
            list.isEmpty() -> {
                clearSelection()
                _routeState.value = AppRouteState.OrgRouting
            }
            !hasActive && hasPending -> {
                select(list.first())
                _routeState.value = AppRouteState.PendingApproval
            }
            else -> {
                val active = list.firstOrNull { it.status.equals("active", ignoreCase = true) } ?: list.first()
                select(active)
                _routeState.value = AppRouteState.Active
            }
        }
    }

    fun select(household: JoinedHousehold) {
        _selectedHouseholdId.value = household.householdId
        _selectedMembershipId.value = household.membershipId
        _selectedProfileId.value = household.profileId
    }

    private fun clearSelection() {
        _selectedHouseholdId.value = null
        _selectedMembershipId.value = null
        _selectedProfileId.value = null
    }

    fun markBootstrapping() {
        _routeState.value = AppRouteState.Bootstrapping
    }
}
