package com.aifamilygroup.reminder.data.auth

import android.util.Log
import com.aifamilygroup.reminder.data.session.AppSession
import com.aifamilygroup.reminder.domain.model.JoinedHousehold
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.Google
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.providers.builtin.IDToken
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

private const val AUTH_GOOGLE_TAG = "AuthGoogle"

@Singleton
class AuthRepository @Inject constructor(
    private val client: SupabaseClient,
    private val session: AppSession,
) {
    suspend fun bootstrap() {
        session.markBootstrapping()
        val user = runCatching { client.auth.currentUserOrNull() }.getOrNull()
        if (user == null) {
            session.setUnauthenticated()
            return
        }
        session.setUser(user.id)
        refreshHouseholds()
    }

    suspend fun signInWithEmail(email: String, password: String) {
        client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
        val user = client.auth.currentUserOrNull() ?: error("Sign-in succeeded but no user")
        session.setUser(user.id)
        refreshHouseholds()
    }

    suspend fun signInWithGoogleIdToken(idToken: String, nonce: String? = null) {
        Log.i(
            AUTH_GOOGLE_TAG,
            "repo step=signInWith_IDToken begin idTokenLen=${idToken.length} nonceNull=${nonce == null}",
        )
        client.auth.signInWith(IDToken) {
            this.idToken = idToken
            provider = Google
            this.nonce = nonce
        }
        val user = client.auth.currentUserOrNull()
        if (user == null) {
            Log.e(AUTH_GOOGLE_TAG, "repo step=no_user_after_id_token")
            error("Google sign-in succeeded but no user")
        }
        Log.i(AUTH_GOOGLE_TAG, "repo step=user_ok userId=${user.id} → refreshHouseholds")
        session.setUser(user.id)
        refreshHouseholds()
        Log.i(AUTH_GOOGLE_TAG, "repo step=done")
    }

    /** Anonymous/guest path for MVP parity with iOS guest onboarding. */
    suspend fun signInAnonymously() {
        client.auth.signInAnonymously()
        val user = client.auth.currentUserOrNull() ?: error("Anonymous sign-in failed")
        session.setUser(user.id)
        refreshHouseholds()
    }

    suspend fun signOut() {
        runCatching { client.auth.signOut() }
        session.setUnauthenticated()
    }

    suspend fun refreshHouseholds() {
        val rows = runCatching {
            client.postgrest.rpc("fetch_my_joined_households").decodeList<JoinedHousehold>()
        }.getOrElse {
            // Fallback: empty → OrgRouting; real RPC name may vary per deployment.
            emptyList()
        }
        session.applyHouseholds(rows)
    }

    suspend fun createHousehold(name: String) {
        val trimmed = name.trim()
        client.postgrest.rpc(
            "create_household_with_creator",
            buildJsonObject { put("p_name", trimmed) },
        )
        session.pendingPreferredHouseholdName = trimmed
        refreshHouseholds()
    }

    suspend fun joinHousehold(inviteCode: String) {
        client.postgrest.rpc(
            "request_join_household",
            buildJsonObject { put("p_invite_code", inviteCode.trim().uppercase()) },
        )
        refreshHouseholds()
    }
}
