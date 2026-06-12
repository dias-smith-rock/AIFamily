import SwiftUI

/// Displays task duration using localized hour/minute formatting.
struct TaskDurationText: View {
    @Environment(\.locale) private var locale
    let minutes: Int

    var body: some View {
        Text(TaskDurationFormatting.readableDuration(minutes: minutes, locale: locale))
    }
}
