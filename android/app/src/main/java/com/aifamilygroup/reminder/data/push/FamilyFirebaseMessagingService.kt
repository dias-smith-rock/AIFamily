package com.aifamilygroup.reminder.data.push

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

/**
 * FCM entry point. Register the Android app in the same Firebase project as iOS,
 * drop `google-services.json` into `android/app/`, and enable the Google Services plugin.
 */
class FamilyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        Log.i(TAG, "FCM token refreshed (length=${token.length})")
        // TODO: upsert device token → Supabase (membership-scoped) when RPC is ready.
    }

    override fun onMessageReceived(message: RemoteMessage) {
        Log.i(TAG, "FCM message from=${message.from} data=${message.data.keys}")
    }

    companion object {
        private const val TAG = "FamilyFCM"
    }
}
