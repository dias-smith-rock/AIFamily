//
//  reminderApp.swift
//  reminder
//
//  Created by Rock on 27/4/2026.
//

import SwiftUI
import SwiftData

@main
struct WeFamilyApp: App {
    @StateObject private var appBootstrap = AppBootstrap()
    @StateObject private var appRouter = AppRouter()
    @StateObject private var appSettings = AppSettingsManager.shared

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
                .environment(\.locale, appSettings.selectedLanguage.locale)
                .environment(\.layoutDirection, appSettings.selectedLanguage.layoutDirection)
                .preferredColorScheme(appSettings.colorScheme)
                .applyAppTextSize()
                .tint(AppTheme.ColorToken.accent)
        }
        .modelContainer(sharedModelContainer)
    }
}
