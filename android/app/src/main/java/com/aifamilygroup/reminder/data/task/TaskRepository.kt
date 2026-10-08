package com.aifamilygroup.reminder.data.task

import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.domain.model.CompleteTaskWithSpatialParams
import com.aifamilygroup.reminder.domain.model.CreateTaskWithSpatialParams
import com.aifamilygroup.reminder.domain.model.FamilyTask
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class TaskRepository @Inject constructor(
    private val client: SupabaseClient,
    private val session: AppSession,
) {
    suspend fun fetchScheduledTasks(householdId: String): List<FamilyTask> {
        return client.from("tasks")
            .select {
                filter {
                    eq("household_id", householdId)
                    neq("task_type", "flexible")
                }
            }
            .decodeList()
    }

    suspend fun fetchTodos(householdId: String): List<FamilyTask> {
        return client.from("tasks")
            .select {
                filter {
                    eq("household_id", householdId)
                    eq("task_type", "flexible")
                }
            }
            .decodeList()
    }

    suspend fun createScheduledTask(title: String, description: String? = null): FamilyTask? {
        val householdId = session.selectedHouseholdId.value ?: return null
        val membershipId = session.selectedMembershipId.value ?: return null
        val params = CreateTaskWithSpatialParams(
            title = title,
            description = description,
            creatorId = membershipId,
            tenantId = householdId,
            geofence = null,
        )
        return client.postgrest.rpc("create_task_with_spatial", params).decodeSingleOrNull()
    }

    suspend fun completeTask(taskId: String) {
        val membershipId = session.selectedMembershipId.value ?: return
        val params = CompleteTaskWithSpatialParams(
            taskId = taskId,
            userId = membershipId,
            completionLocation = null,
        )
        client.postgrest.rpc("complete_task_with_spatial", params)
    }

    suspend fun updateTaskStatus(taskId: String, status: String) {
        client.from("tasks").update(buildJsonObject { put("status", status) }) {
            filter { eq("id", taskId) }
        }
    }
}
