package com.aifamilygroup.reminder.data.session

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/** Persists last-entered household per user (parity with iOS lastHouseholdId). */
@Singleton
class HouseholdPreferenceStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun lastHouseholdId(userId: String): String? =
        prefs.getString(key(userId), null)

    fun saveLastHouseholdId(userId: String, householdId: String) {
        prefs.edit().putString(key(userId), householdId).apply()
    }

    fun clear(userId: String) {
        prefs.edit().remove(key(userId)).apply()
    }

    private fun key(userId: String) = "last_household_$userId"

    private companion object {
        const val PREFS = "household_routing"
    }
}
