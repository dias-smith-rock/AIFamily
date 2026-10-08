package com.aifamilygroup.reminder.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.data.task.TaskRepository
import com.aifamilygroup.reminder.domain.model.FamilyTask
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import kotlinx.datetime.Clock
import kotlinx.datetime.LocalDate
import kotlinx.datetime.TimeZone
import kotlinx.datetime.toLocalDateTime
import javax.inject.Inject

@HiltViewModel
class ScheduleViewModel @Inject constructor(
    private val taskRepository: TaskRepository,
    private val session: AppSession,
) : ViewModel() {

    private val _tasks = MutableStateFlow<List<FamilyTask>>(emptyList())
    val tasks: StateFlow<List<FamilyTask>> = _tasks.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    private val _selectedDay = MutableStateFlow(today())
    val selectedDay: StateFlow<LocalDate> = _selectedDay.asStateFlow()

    init {
        viewModelScope.launch {
            session.selectedHouseholdId.collectLatest { householdId ->
                if (householdId != null) reload()
            }
        }
    }

    fun selectDay(day: LocalDate) {
        _selectedDay.value = day
    }

    fun reload() {
        val householdId = session.selectedHouseholdId.value ?: return
        viewModelScope.launch {
            _isLoading.value = true
            _error.value = null
            runCatching { taskRepository.fetchScheduledTasks(householdId) }
                .onSuccess { _tasks.value = it.sortedBy { t -> t.dueDate } }
                .onFailure { _error.value = it.message }
            _isLoading.value = false
        }
    }

    fun tasksForSelectedDay(): List<FamilyTask> {
        val day = _selectedDay.value.toString()
        return _tasks.value.filter { task ->
            val due = task.dueDate ?: return@filter false
            due.startsWith(day)
        }
    }

    fun createTask(title: String) {
        if (title.isBlank()) return
        viewModelScope.launch {
            runCatching { taskRepository.createScheduledTask(title.trim()) }
                .onSuccess { reload() }
                .onFailure { _error.value = it.message }
        }
    }

    fun complete(task: FamilyTask) {
        viewModelScope.launch {
            runCatching { taskRepository.completeTask(task.id) }
                .onSuccess { reload() }
                .onFailure { _error.value = it.message }
        }
    }

    private fun today(): LocalDate =
        Clock.System.now().toLocalDateTime(TimeZone.currentSystemDefault()).date
}
