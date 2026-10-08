package com.aifamilygroup.reminder.domain.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Identity note (shared with iOS):
 * - `creator_id` / `involved_member_ids` use **household_memberships.id**, not auth.users.id.
 * - Location `entity_id` uses **family_profiles.id**.
 */

@Serializable
data class FamilyTask(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("creator_id") val creatorId: String,
    val title: String,
    val description: String? = null,
    @SerialName("task_type") val taskType: String = "scheduled",
    val status: String = "new",
    @SerialName("due_date") val dueDate: String? = null,
    @SerialName("is_all_day") val isAllDay: Boolean = false,
    @SerialName("involved_member_ids") val involvedMemberIds: List<String> = emptyList(),
    @SerialName("end_datetime") val endDatetime: String? = null,
    @SerialName("duration_minutes") val durationMinutes: Int? = null,
    val timezone: String? = null,
)

@Serializable
data class CreateTaskWithSpatialParams(
    @SerialName("p_title") val title: String,
    @SerialName("p_description") val description: String? = null,
    @SerialName("p_creator_id") val creatorId: String,
    @SerialName("p_tenant_id") val tenantId: String,
    @SerialName("p_geofence") val geofence: Map<String, String>? = null,
)

@Serializable
data class CompleteTaskWithSpatialParams(
    @SerialName("p_task_id") val taskId: String,
    @SerialName("p_user_id") val userId: String,
    @SerialName("p_completion_location") val completionLocation: Map<String, String>? = null,
)

@Serializable
data class JoinedHousehold(
    @SerialName("household_id") val householdId: String,
    @SerialName("membership_id") val membershipId: String,
    @SerialName("profile_id") val profileId: String? = null,
    @SerialName("household_name") val householdName: String? = null,
    val role: String? = null,
    val status: String? = null,
)

@Serializable
data class HouseholdMembership(
    val id: String,
    @SerialName("household_id") val householdId: String,
    @SerialName("user_id") val userId: String? = null,
    @SerialName("profile_id") val profileId: String? = null,
    val nickname: String? = null,
    val role: String? = null,
    val status: String? = null,
)

@Serializable
data class TodoItem(
    val id: String,
    val title: String,
    val status: String = "new",
    @SerialName("household_id") val householdId: String,
    @SerialName("is_all_day") val isAllDay: Boolean = true,
    @SerialName("task_type") val taskType: String = "flexible",
)

@Serializable
data class LedgerTransaction(
    val id: String,
    @SerialName("household_id") val householdId: String,
    val amount: Long,
    val type: String,
    @SerialName("category_name_snapshot") val categoryName: String? = null,
    val note: String? = null,
    @SerialName("occurred_at") val occurredAt: String? = null,
)

@Serializable
data class LocationStateRecord(
    val id: String? = null,
    @SerialName("household_id") val householdId: String,
    @SerialName("entity_id") val profileId: String,
    val locations: List<LocationPayload> = emptyList(),
    @SerialName("is_ghost_mode") val isGhostMode: Boolean = false,
    @SerialName("updated_at") val updatedAt: String? = null,
)

@Serializable
data class LocationPayload(
    val lat: Double,
    val lng: Double,
    @SerialName("address_name") val addressName: String? = null,
    @SerialName("recorded_at") val recordedAt: String? = null,
    @SerialName("battery_level") val batteryLevel: Int? = null,
    @SerialName("is_charging") val isCharging: Boolean? = null,
)

@Serializable
data class MemberListRow(
    val membershipId: String,
    val profileId: String?,
    val displayName: String,
    val latest: LocationPayload? = null,
    val isGhostMode: Boolean = false,
)

enum class AppRouteState {
    Bootstrapping,
    Unauthenticated,
    /** No active household — create / join onboarding (iOS `.orgRouting`). */
    OrgRouting,
    /** Multiple active households — pick one (iOS `.householdSelection`). */
    HouseholdSelection,
    PendingApproval,
    Active,
}
