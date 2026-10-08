package com.aifamilygroup.reminder.ui.todos

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aifamilygroup.reminder.R
import com.aifamilygroup.reminder.domain.model.FamilyTask
import com.aifamilygroup.reminder.viewmodel.TodosViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TodosScreen(viewModel: TodosViewModel = hiltViewModel()) {
    val todos by viewModel.todos.collectAsStateWithLifecycle()
    val error by viewModel.error.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.common_to_dos)) },
                actions = {
                    TextButton(onClick = viewModel::reload) {
                        Text(stringResource(R.string.common_reload))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 16.dp),
        ) {
            error?.let {
                Text(
                    it,
                    color = MaterialTheme.colorScheme.error,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            }
            if (todos.isEmpty()) {
                Text(
                    "No to-dos yet",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.secondary,
                    modifier = Modifier.padding(top = 40.dp),
                )
            } else {
                TodoList(
                    todos = todos,
                    onComplete = viewModel::complete,
                )
            }
        }
    }
}

@Composable
private fun TodoList(
    todos: List<FamilyTask>,
    onComplete: (FamilyTask) -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        items(
            items = todos,
            key = { todo -> todo.id },
        ) { todo ->
            TodoRow(todo = todo, onComplete = onComplete)
        }
    }
}

@Composable
private fun TodoRow(
    todo: FamilyTask,
    onComplete: (FamilyTask) -> Unit,
) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(todo.title, style = MaterialTheme.typography.titleMedium)
                Text(todo.status, style = MaterialTheme.typography.bodySmall)
            }
            if (!todo.status.equals("completed", ignoreCase = true)) {
                IconButton(onClick = { onComplete(todo) }) {
                    Icon(Icons.Default.CheckCircle, contentDescription = null)
                }
            }
        }
    }
}
