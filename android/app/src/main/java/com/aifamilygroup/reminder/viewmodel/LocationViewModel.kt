package com.aifamilygroup.reminder.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifamilygroup.reminder.data.location.LocationRepository
import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.domain.model.MemberListRow
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class LocationViewModel @Inject constructor(
    private val locationRepository: LocationRepository,
    private val session: AppSession,
) : ViewModel() {
    private val _members = MutableStateFlow<List<MemberListRow>>(emptyList())
    val members: StateFlow<List<MemberListRow>> = _members.asStateFlow()

    private val _hideLocation = MutableStateFlow(false)
    val hideLocation: StateFlow<Boolean> = _hideLocation.asStateFlow()

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
            runCatching { locationRepository.fetchMemberRows(householdId) }
                .onSuccess { _members.value = it }
                .onFailure { _error.value = it.message }
        }
    }

    fun setHideLocation(enabled: Boolean) {
        _hideLocation.value = enabled
        // Local preference only for MVP (matches iOS ghost pref semantics).
    }
}
