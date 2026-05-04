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
        }
        .modelContainer(sharedModelContainer)
    }
}
