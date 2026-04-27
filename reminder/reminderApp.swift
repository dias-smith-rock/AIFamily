//
//  reminderApp.swift
//  reminder
//
//  Created by Rock on 27/4/2026.
//

import SwiftUI
import SwiftData

@main
struct reminderApp: App {
    @StateObject private var appBootstrap = AppBootstrap()

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
                .environmentObject(appBootstrap)
                .environmentObject(appBootstrap.viewModelFactory)
        }
        .modelContainer(sharedModelContainer)
    }
}
