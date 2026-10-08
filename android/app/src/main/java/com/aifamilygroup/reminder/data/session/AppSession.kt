package com.aifamilygroup.reminder.data.session

import com.aifamilygroup.reminder.domain.model.AppRouteState
import com.aifamilygroup.reminder.domain.model.JoinedHousehold
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class AppSession @Inject constructor(
    private val householdPrefs: HouseholdPreferenceStore,
) {
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

    /** After create/join, prefer entering this household on next [applyHouseholds]. */
    var pendingPreferredHouseholdId: String? = null
    var pendingPreferredHouseholdName: String? = null

    fun setUnauthenticated() {
        _userId.value = null
        _households.value = emptyList()
        clearSelection()
        pendingPreferredHouseholdId = null
        pendingPreferredHouseholdName = null
        _routeState.value = AppRouteState.Unauthenticated
    }

    fun setUser(userId: String) {
        _userId.value = userId
    }

    /**
     * iOS AppRouter.refreshStateFromBackend parity:
     * - no active → OrgRouting (or PendingApproval if only pending/invited)
     * - one active → enter directly
     * - multiple + last/preferred/current → enter that one
     * - multiple otherwise → HouseholdSelection
     */
    fun applyHouseholds(list: List<JoinedHousehold>) {
        _households.value = list
        val active = list.filter { it.isActiveMembership }
        val hasPending = list.any { it.isPendingMembership }

        if (active.isEmpty()) {
            clearSelection()
            _routeState.value = if (hasPending) {
                AppRouteState.PendingApproval
            } else {
                AppRouteState.OrgRouting
            }
            return
        }

        val preferredId = pendingPreferredHouseholdId
        val preferredName = pendingPreferredHouseholdName
        pendingPreferredHouseholdId = null
        pendingPreferredHouseholdName = null

        val preferred = when {
            preferredId != null -> active.firstOrNull { it.householdId == preferredId }
            !preferredName.isNullOrBlank() ->
                active.firstOrNull { it.householdName.equals(preferredName, ignoreCase = true) }
            else -> null
        }
        if (preferred != null) {
            enterHousehold(preferred)
            return
        }

        if (active.size == 1) {
            enterHousehold(active.first())
            return
        }

        val userId = _userId.value
        val lastId = userId?.let { householdPrefs.lastHouseholdId(it) }
        val last = lastId?.let { id -> active.firstOrNull { it.householdId == id } }
        if (last != null) {
            enterHousehold(last)
            return
        }

        val currentId = _selectedHouseholdId.value
        val current = currentId?.let { id -> active.firstOrNull { it.householdId == id } }
        if (current != null) {
            enterHousehold(current)
            return
        }

        clearSelection()
        _routeState.value = AppRouteState.HouseholdSelection
    }

    fun enterHousehold(household: JoinedHousehold) {
        select(household)
        _userId.value?.let { householdPrefs.saveLastHouseholdId(it, household.householdId) }
        _routeState.value = AppRouteState.Active
    }

    fun select(household: JoinedHousehold) {
        _selectedHouseholdId.value = household.householdId
        _selectedMembershipId.value = household.membershipId
        _selectedProfileId.value = household.profileId
    }

    fun goToOrgRouting() {
        clearSelection()
        _routeState.value = AppRouteState.OrgRouting
    }

    fun goToHouseholdSelection() {
        clearSelection()
        _routeState.value = AppRouteState.HouseholdSelection
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

private val JoinedHousehold.isActiveMembership: Boolean
    get() {
        val s = status?.trim()?.lowercase().orEmpty()
        return s.isEmpty() || s == "active"
    }

private val JoinedHousehold.isPendingMembership: Boolean
    get() {
        val s = status?.trim()?.lowercase().orEmpty()
        return s == "pending" || s == "invited"
    }
