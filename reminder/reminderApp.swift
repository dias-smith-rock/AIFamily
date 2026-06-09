//
//  reminderApp.swift
//  reminder
//
//  Created by Rock on 27/4/2026.
//

import SwiftUI
import SwiftData
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

@main
struct WeFamilyApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var firebaseAppDelegate
    #endif

    @StateObject private var appBootstrap = AppBootstrap()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var appSettings = AppSettingsManager.shared

    init() {
        BackgroundLocationPreferences.registerDefaults()
        LocationPersistPreferences.registerDefaults()
        FirebaseAppDelegate.configureFirebaseIfNeeded()
        UNUserNotificationCenter.current().delegate = TaskReminderNotificationDelegate.shared
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appRouter)
                .environmentObject(appBootstrap)
                .environmentObject(appBootstrap.viewModelFactory)
                .environmentObject(appSettings)
                .appLocaleEnvironment(using: appSettings)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .preferredColorScheme(appSettings.colorScheme)
                .applyAppTextSize()
                .tint(AppTheme.ColorToken.accent)
        }
        .modelContainer(sharedModelContainer)
    }
}
