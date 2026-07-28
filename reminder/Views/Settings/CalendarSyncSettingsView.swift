import SwiftUI

struct CalendarSyncSettingsView: View {
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appRouter: AppRouter
    @EnvironmentObject private var appSettings: AppSettingsManager
    @StateObject private var viewModel = CalendarSyncViewModel()
    @State private var isShowingHouseholdPicker = false

    var body: some View {
        List {
            Section {
                if viewModel.hasAccess == false {
                    Text(L10n.Settings.calendarSyncPermissionNeeded.localized)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.authorizationDenied {
                        Button(L10n.Settings.calendarSyncOpenSettings) {
                            viewModel.openSystemSettings()
                        }
                    } else {
                        Button(L10n.Settings.calendarSyncGrantAccess) {
                            Task { await viewModel.requestAccess() }
                        }
                        .disabled(viewModel.isRequestingAccess)
                    }
                } else {
                    Toggle(isOn: Binding(
                        get: { viewModel.continuousEnabled },
                        set: { viewModel.setContinuousEnabled($0) }
                    )) {
                        Text(L10n.Settings.calendarSyncContinuous.localized)
                    }
                }
            } footer: {
                Text(L10n.Settings.calendarSyncFooter.localized)
            }

            Section {
                HStack {
                    Text(L10n.Settings.calendarSyncTargetGroup.localized)
                    Spacer()
                    Text(currentHouseholdName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button(L10n.Settings.calendarSyncChangeGroup) {
                    isShowingHouseholdPicker = true
                }
            } header: {
                Text(L10n.Settings.calendarSyncTargetGroup.localized)
            }

            if viewModel.hasAccess {
                Section {
                    if viewModel.calendars.isEmpty {
                        Text(L10n.Settings.calendarSyncNoCalendars.localized)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.calendars) { calendar in
                            Button {
                                viewModel.toggleCalendar(calendar.id)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: viewModel.selectedCalendarIds.contains(calendar.id)
                                          ? "checkmark.circle.fill"
                                          : "circle")
                                        .foregroundStyle(
                                            viewModel.selectedCalendarIds.contains(calendar.id)
                                            ? Color.accentColor
                                            : Color.secondary
                                        )
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(calendar.title)
                                            .foregroundStyle(.primary)
                                        Text(viewModel.sourceLabel(for: calendar.sourceLabel).localized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(L10n.Settings.calendarSyncCalendarsSection.localized)
                }
            }

            Section {
                Button {
                    Task {
                        await viewModel.sync(
                            householdId: appRouter.selectedHouseholdId,
                            membershipId: appRouter.selectedMembershipId
                        )
                    }
                } label: {
                    HStack {
                        Spacer()
                        if viewModel.isSyncing {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text(L10n.Settings.calendarSyncInProgress.localized)
                        } else {
                            Text(L10n.Settings.calendarSyncStart.localized)
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(
                    viewModel.isSyncing
                        || appRouter.selectedHouseholdId == nil
                        || viewModel.selectedCalendarIds.isEmpty
                )

                Text(lastSyncedLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let statusMessage = viewModel.statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(L10n.Settings.calendarSyncNavTitle.localized)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.onAppear()
            if appRouter.selectedHouseholdId == nil {
                isShowingHouseholdPicker = true
            }
        }
        .sheet(isPresented: $isShowingHouseholdPicker) {
            WriteTargetHouseholdPicker { _ in }
                .environmentObject(appRouter)
                .environment(\.locale, appSettings.appLocale)
                .environment(\.layoutDirection, appSettings.layoutDirection)
                .presentationDetents([.medium])
        }
    }

    private var currentHouseholdName: String {
        guard let id = appRouter.selectedHouseholdId,
              let option = appRouter.selectableHouseholds.first(where: { $0.id == id }) else {
            return AppLocalized.string(L10n.Settings.calendarSyncSelectGroup, locale: locale)
        }
        return option.name
    }

    private var lastSyncedLabel: String {
        if let date = viewModel.lastSyncedAt {
            let formatted = date.formatted(
                .dateTime
                    .year()
                    .month()
                    .day()
                    .hour()
                    .minute()
                    .locale(locale)
            )
            return L10n.Settings.calendarSyncLastSynced.formatted(locale: locale, formatted)
        }
        return AppLocalized.string(L10n.Settings.calendarSyncNever, locale: locale)
    }
}

#Preview {
    NavigationStack {
        CalendarSyncSettingsView()
            .environmentObject(AppRouter())
            .environmentObject(AppSettingsManager.shared)
    }
}
