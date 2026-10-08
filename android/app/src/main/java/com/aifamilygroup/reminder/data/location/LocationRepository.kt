package com.aifamilygroup.reminder.data.location

import com.aifamilygroup.reminder.domain.model.HouseholdMembership
import com.aifamilygroup.reminder.domain.model.LocationStateRecord
import com.aifamilygroup.reminder.domain.model.MemberListRow
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class LocationRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    suspend fun fetchMemberRows(householdId: String): List<MemberListRow> {
        val memberships = client.from("household_memberships")
            .select {
                filter {
                    eq("household_id", householdId)
                    eq("status", "active")
                }
            }
            .decodeList<HouseholdMembership>()

        val states = client.from("location_states")
            .select {
                filter { eq("household_id", householdId) }
            }
            .decodeList<LocationStateRecord>()
            .associateBy { it.profileId }

        return memberships.map { m ->
            val state = m.profileId?.let { states[it] }
            MemberListRow(
                membershipId = m.id,
                profileId = m.profileId,
                displayName = m.nickname?.takeIf { it.isNotBlank() } ?: "Unknown member",
                latest = state?.locations?.firstOrNull(),
                isGhostMode = state?.isGhostMode == true,
            )
        }
    }
}
