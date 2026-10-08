package com.aifamilygroup.reminder.ui.auth

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.aifamilygroup.reminder.BuildConfig
import com.aifamilygroup.reminder.R
import com.aifamilygroup.reminder.viewmodel.RootViewModel
import com.google.android.gms.auth.api.signin.GoogleSignIn
import com.google.android.gms.auth.api.signin.GoogleSignInOptions
import com.google.android.gms.common.api.ApiException

private val LoginBlack = Color.Black
private val LoginSecondary = Color.White.copy(alpha = 0.82f)
private val LoginFooter = Color.White.copy(alpha = 0.55f)
private val LoginLink = Color.White.copy(alpha = 0.85f)
private val GoogleBlue = Color(0xFF007AFF)
private val GuestFill = Color.White.copy(alpha = 0.14f)
private val GuestStroke = Color.White.copy(alpha = 0.28f)

private enum class LoginProvider { Google, Guest }

private const val AUTH_GOOGLE_TAG = "AuthGoogle"

@Composable
fun LoginScreen(viewModel: RootViewModel) {
    val context = LocalContext.current
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf<LoginProvider?>(null) }

    val googleLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult(),
    ) { result ->
        val resultLabel = when (result.resultCode) {
            Activity.RESULT_OK -> "RESULT_OK"
            Activity.RESULT_CANCELED -> "RESULT_CANCELED"
            else -> "resultCode=${result.resultCode}"
        }
        Log.i(
            AUTH_GOOGLE_TAG,
            "activityResult step=play_services_return $resultLabel dataNull=${result.data == null}",
        )

        // Even on non-OK, parse intent — ApiException.statusCode often reveals DEVELOPER_ERROR etc.
        val apiStatus = runCatching {
            GoogleSignIn.getSignedInAccountFromIntent(result.data)
                .getResult(ApiException::class.java)
            null
        }.exceptionOrNull()

        if (apiStatus is ApiException) {
            Log.w(
                AUTH_GOOGLE_TAG,
                "activityResult step=parse_account ApiException status=${apiStatus.statusCode} message=${apiStatus.message}",
            )
        } else if (apiStatus != null) {
            Log.w(
                AUTH_GOOGLE_TAG,
                "activityResult step=parse_account error=${apiStatus.javaClass.simpleName}: ${apiStatus.message}",
            )
        }

        if (result.resultCode != Activity.RESULT_OK) {
            loading = null
            val statusCode = (apiStatus as? ApiException)?.statusCode
            // 10 = CommonStatusCodes.DEVELOPER_ERROR (SHA-1 / package / OAuth client mismatch)
            error = when (statusCode) {
                10 -> {
                    Log.e(
                        AUTH_GOOGLE_TAG,
                        "activityResult step=developer_error status=10 " +
                            "package=${context.packageName} " +
                            "hint=register_Android_OAuth_client_with_this_package_and_debug_SHA1",
                    )
                    context.getString(R.string.auth_google_developer_error, context.packageName)
                }
                12501 -> {
                    Log.w(AUTH_GOOGLE_TAG, "activityResult step=user_cancelled status=12501")
                    context.getString(R.string.auth_google_sign_in_cancelled)
                }
                else -> {
                    Log.w(
                        AUTH_GOOGLE_TAG,
                        "activityResult step=non_ok status=$statusCode result=$resultLabel",
                    )
                    if (result.resultCode == Activity.RESULT_CANCELED) {
                        context.getString(R.string.auth_google_sign_in_cancelled)
                    } else {
                        context.getString(R.string.auth_google_sign_in_failed)
                    }
                }
            }
            return@rememberLauncherForActivityResult
        }

        try {
            val account = GoogleSignIn.getSignedInAccountFromIntent(result.data)
                .getResult(ApiException::class.java)
            val idToken = account.idToken
            Log.i(
                AUTH_GOOGLE_TAG,
                "activityResult step=account_ok email=${account.email} " +
                    "idTokenLen=${idToken?.length ?: 0} hasServerAuthCode=${!account.serverAuthCode.isNullOrBlank()}",
            )
            if (idToken.isNullOrBlank()) {
                loading = null
                Log.e(
                    AUTH_GOOGLE_TAG,
                    "activityResult step=missing_id_token " +
                        "hint=requestIdToken(webClientId) must be OAuth Web client, not Android client",
                )
                error = context.getString(R.string.auth_google_sign_in_failed)
                return@rememberLauncherForActivityResult
            }
            Log.i(AUTH_GOOGLE_TAG, "activityResult step=handoff_to_supabase idTokenLen=${idToken.length}")
            viewModel.signInWithGoogleIdToken(idToken) { message ->
                loading = null
                if (message != null) {
                    Log.e(AUTH_GOOGLE_TAG, "supabase step=failed message=$message")
                    error = message
                } else {
                    Log.i(AUTH_GOOGLE_TAG, "supabase step=success")
                }
            }
        } catch (e: ApiException) {
            loading = null
            Log.e(
                AUTH_GOOGLE_TAG,
                "activityResult step=get_account_failed ApiException status=${e.statusCode} message=${e.message}",
                e,
            )
            error = context.getString(R.string.auth_google_sign_in_failed)
        } catch (e: Exception) {
            loading = null
            Log.e(AUTH_GOOGLE_TAG, "activityResult step=get_account_failed unexpected", e)
            error = context.getString(R.string.auth_google_sign_in_failed)
        }
    }

    fun startGoogleSignIn() {
        error = null
        val webClientId = BuildConfig.GOOGLE_WEB_CLIENT_ID
        Log.i(
            AUTH_GOOGLE_TAG,
            "start step=tap webClientIdBlank=${webClientId.isBlank()} " +
                "webClientIdPrefix=${webClientId.take(24)}… package=${context.packageName}",
        )
        if (webClientId.isBlank()) {
            Log.e(AUTH_GOOGLE_TAG, "start step=abort_missing_web_client_id")
            error = context.getString(R.string.auth_google_not_configured)
            return
        }
        loading = LoginProvider.Google
        val gso = GoogleSignInOptions.Builder(GoogleSignInOptions.DEFAULT_SIGN_IN)
            .requestIdToken(webClientId)
            .requestEmail()
            .build()
        val client = GoogleSignIn.getClient(context, gso)
        Log.i(AUTH_GOOGLE_TAG, "start step=launch_play_services_intent")
        googleLauncher.launch(client.signInIntent)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(LoginBlack)
            .padding(horizontal = 24.dp),
    ) {
        Spacer(Modifier.weight(1f))

        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(18.dp),
        ) {
            Image(
                painter = painterResource(R.drawable.app_logo),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier
                    .size(82.dp)
                    .clip(RoundedCornerShape(18.dp)),
            )
            Text(
                text = stringResource(R.string.common_from_chaos_to_clarity_together_perfectly_synced),
                color = LoginSecondary,
                fontSize = 17.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                lineHeight = 24.sp,
            )
        }

        Spacer(Modifier.weight(1.2f))

        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            LoginActionButton(
                background = GoogleBlue,
                enabled = loading == null,
                onClick = { startGoogleSignIn() },
            ) {
                if (loading == LoginProvider.Google) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                } else {
                    GoogleGlyph()
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    text = stringResource(R.string.common_continue_with_google),
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 16.sp,
                    color = Color.White,
                )
            }

            LoginActionButton(
                background = GuestFill,
                enabled = loading == null,
                onClick = {
                    error = null
                    loading = LoginProvider.Guest
                    viewModel.signInGuest { message ->
                        loading = null
                        if (message != null) error = message
                    }
                },
                borderColor = GuestStroke,
            ) {
                if (loading == LoginProvider.Guest) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        color = Color.White,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(
                        imageVector = Icons.Outlined.AccountCircle,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(22.dp),
                    )
                }
                Spacer(Modifier.width(10.dp))
                Text(
                    text = stringResource(R.string.auth_guest_experience_no_signup),
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 16.sp,
                    color = Color.White,
                )
            }

            error?.let {
                Text(
                    text = it,
                    color = Color(0xFFFF6B6B),
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 4.dp),
                )
            }
        }

        Spacer(Modifier.weight(0.55f))

        LegalConsentFooter(
            onPrivacy = {
                context.startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(context.getString(R.string.legal_privacy_url))),
                )
            },
            onTerms = {
                context.startActivity(
                    Intent(Intent.ACTION_VIEW, Uri.parse(context.getString(R.string.legal_terms_url))),
                )
            },
        )
        Spacer(Modifier.height(12.dp))
    }
}

@Composable
private fun LoginActionButton(
    background: Color,
    enabled: Boolean,
    onClick: () -> Unit,
    borderColor: Color? = null,
    content: @Composable () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(background)
            .then(
                if (borderColor != null) {
                    Modifier.border(1.dp, borderColor, RoundedCornerShape(12.dp))
                } else {
                    Modifier
                },
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        content()
    }
}

@Composable
private fun GoogleGlyph() {
    Box(
        modifier = Modifier
            .size(20.dp)
            .clip(CircleShape)
            .background(Color.White),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = "G",
            color = GoogleBlue,
            fontWeight = FontWeight.Bold,
            fontSize = 12.sp,
        )
    }
}

@Composable
private fun LegalConsentFooter(
    onPrivacy: () -> Unit,
    onTerms: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(
            text = stringResource(R.string.auth_by_signing_in_you_agree_to_this_app_s),
            color = LoginFooter,
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = stringResource(R.string.common_privacy_policy),
                color = LoginLink,
                fontSize = 12.sp,
                textDecoration = TextDecoration.Underline,
                modifier = Modifier.clickable(onClick = onPrivacy),
            )
            Text(
                text = " ${stringResource(R.string.common_and)} ",
                color = LoginFooter,
                fontSize = 12.sp,
            )
            Text(
                text = stringResource(R.string.common_terms_of_service),
                color = LoginLink,
                fontSize = 12.sp,
                textDecoration = TextDecoration.Underline,
                modifier = Modifier.clickable(onClick = onTerms),
            )
        }
    }
}
