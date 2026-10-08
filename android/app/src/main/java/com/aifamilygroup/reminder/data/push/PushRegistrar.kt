package com.aifamilygroup.reminder.data.push

import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PushRegistrar @Inject constructor() {
    fun register() {
        runCatching {
            FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
                if (!task.isSuccessful) {
                    Log.w(TAG, "FCM token fetch failed", task.exception)
                    return@addOnCompleteListener
                }
                Log.i(TAG, "FCM token ready")
            }
        }.onFailure {
            Log.w(TAG, "Firebase not configured yet (missing google-services.json)", it)
        }
    }

    companion object {
        private const val TAG = "PushRegistrar"
    }
}
