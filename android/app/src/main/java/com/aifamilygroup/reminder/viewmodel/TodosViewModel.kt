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
import javax.inject.Inject

@HiltViewModel
class TodosViewModel @Inject constructor(
    private val taskRepository: TaskRepository,
    private val session: AppSession,
) : ViewModel() {
    private val _todos = MutableStateFlow<List<FamilyTask>>(emptyList())
    val todos: StateFlow<List<FamilyTask>> = _todos.asStateFlow()

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
            runCatching { taskRepository.fetchTodos(householdId) }
                .onSuccess { _todos.value = it }
                .onFailure { _error.value = it.message }
        }
    }

    fun complete(todo: FamilyTask) {
        viewModelScope.launch {
            runCatching { taskRepository.completeTask(todo.id) }
                .onSuccess { reload() }
                .onFailure { _error.value = it.message }
        }
    }
}
