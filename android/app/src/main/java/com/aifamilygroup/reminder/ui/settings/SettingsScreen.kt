package com.aifamilygroup.reminder.ui.settings

import android.app.Activity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aifamilygroup.reminder.R
import com.aifamilygroup.reminder.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onSignOut: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel(),
) {
    val hasPremium by viewModel.hasPremium.collectAsStateWithLifecycle()
    val products by viewModel.products.collectAsStateWithLifecycle()
    val billingError by viewModel.billingError.collectAsStateWithLifecycle()
    val activity = LocalContext.current as? Activity

    Scaffold(
        topBar = {
            TopAppBar(title = { Text(stringResource(R.string.common_settings_tab)) })
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(16.dp),
        ) {
            Text("Subscription", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            Text(
                if (hasPremium) "Pro active" else "Free plan",
                color = MaterialTheme.colorScheme.secondary,
            )
            Spacer(Modifier.height(12.dp))
            val product = products.firstOrNull()
            Button(
                onClick = {
                    if (activity != null && product != null) {
                        viewModel.purchase(activity, product)
                    } else {
                        viewModel.refreshBilling()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = !hasPremium,
            ) {
                Text(stringResource(R.string.billing_subscribe_pro))
            }
            Spacer(Modifier.height(8.dp))
            OutlinedButton(
                onClick = viewModel::restore,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(stringResource(R.string.billing_restore_purchases))
            }
            billingError?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.height(32.dp))
            Text(
                "Language / theme follow system for v1. App-locale picker can mirror iOS AppSettingsManager later.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.secondary,
            )
            Spacer(Modifier.height(24.dp))
            OutlinedButton(onClick = onSignOut, modifier = Modifier.fillMaxWidth()) {
                Text("Sign out")
            }
        }
    }
}
