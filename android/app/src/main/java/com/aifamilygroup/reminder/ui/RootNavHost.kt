package com.aifamilygroup.reminder.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.aifamilygroup.reminder.domain.model.AppRouteState
import com.aifamilygroup.reminder.ui.auth.HouseholdSelectionScreen
import com.aifamilygroup.reminder.ui.auth.LoginScreen
import com.aifamilygroup.reminder.ui.auth.OrgRoutingScreen
import com.aifamilygroup.reminder.ui.auth.PendingScreen
import com.aifamilygroup.reminder.ui.main.MainTabScreen
import com.aifamilygroup.reminder.viewmodel.RootViewModel

@Composable
fun RootNavHost(
    viewModel: RootViewModel = hiltViewModel(),
) {
    val route by viewModel.routeState.collectAsStateWithLifecycle()
    when (route) {
        AppRouteState.Bootstrapping -> {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator()
            }
        }
        AppRouteState.Unauthenticated -> LoginScreen(viewModel)
        AppRouteState.OrgRouting -> OrgRoutingScreen(viewModel)
        AppRouteState.HouseholdSelection -> HouseholdSelectionScreen(viewModel)
        AppRouteState.PendingApproval -> PendingScreen(viewModel)
        AppRouteState.Active -> MainTabScreen(onSignOut = viewModel::signOut)
    }
}
