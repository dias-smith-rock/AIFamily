package com.aifamilygroup.reminder.ui.main

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AccountBalanceWallet
import androidx.compose.material.icons.outlined.CalendarMonth
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.aifamilygroup.reminder.R
import com.aifamilygroup.reminder.ui.location.LocationScreen
import com.aifamilygroup.reminder.ui.schedule.ScheduleScreen
import com.aifamilygroup.reminder.ui.settings.SettingsScreen
import com.aifamilygroup.reminder.ui.todos.TodosScreen
import com.aifamilygroup.reminder.ui.wallet.WalletScreen

private enum class MainTab(
    val route: String,
    val labelRes: Int,
    val icon: ImageVector,
) {
    Schedule("schedule", R.string.common_schedule, Icons.Outlined.CalendarMonth),
    Todos("todos", R.string.common_to_dos, Icons.Outlined.Checklist),
    Location("location", R.string.common_location, Icons.Outlined.LocationOn),
    Wallet("wallet", R.string.common_wallet, Icons.Outlined.AccountBalanceWallet),
    Settings("settings", R.string.common_settings_tab, Icons.Outlined.Settings),
}

@Composable
fun MainTabScreen(onSignOut: () -> Unit) {
    val navController = rememberNavController()
    val backStack by navController.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route

    Scaffold(
        bottomBar = {
            NavigationBar {
                MainTab.entries.forEach { tab ->
                    NavigationBarItem(
                        selected = currentRoute == tab.route,
                        onClick = {
                            navController.navigate(tab.route) {
                                popUpTo(navController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                        icon = { Icon(tab.icon, contentDescription = null) },
                        label = { Text(stringResource(tab.labelRes)) },
                    )
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = navController,
            startDestination = MainTab.Schedule.route,
            modifier = Modifier.padding(padding),
        ) {
            composable(MainTab.Schedule.route) { ScheduleScreen() }
            composable(MainTab.Todos.route) { TodosScreen() }
            composable(MainTab.Location.route) { LocationScreen() }
            composable(MainTab.Wallet.route) { WalletScreen() }
            composable(MainTab.Settings.route) { SettingsScreen(onSignOut = onSignOut) }
        }
    }
}
