import SwiftUI
import Kingfisher

//
//  任务详情：纯只读 + 底部状态扭转；编辑经右上角进入 `EditTaskView`。
//  由 `TaskListView` 以 `.sheet(item:)` 弹出，外层包 `NavigationStack`。
//

#if canImport(Supabase)
import Supabase
#endif

private enum RecurringDeleteScope {
    case singleOnly
    case thisAndFuture
}

private struct TaskDetailFormCardStyle: ViewModifier {
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    func body(content: Content) -> some View {
        content
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
    }
}

private extension View {
    func taskDetailFormCardStyled() -> some View {
        modifier(TaskDetailFormCardStyle())
    }
}

struct TaskDetailView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @ObservedObject private var scheduleViewModel: ScheduleViewModel
    @StateObject private var taskDetailViewModel = TaskDetailViewModel()

    private let currentUserRole: MembershipRole
    private let assigneeDisplayNameFallback: String

    @State private var task: FamilyTask
    @State private var showingEditSheet = false
    @State private var isUpdatingStatus = false
    @State private var isDeletingTask = false
    @State private var statusError: String?
    @State private var forWhomProfiles: [FamilyProfile] = []
    @State private var displayRecurrenceRule: String?
    @State private var displayRecurrenceInterval: Int?
    @State private var isShowingDeleteAlert = false
    @State private var attachmentGalleryPresentation: AttachmentGalleryPresentation?
    /// 导航内容区宽度，用于让标题在左右工具区之间居中留白。
    @State private var navigationContentWidth: CGFloat = 0

    init(
        initialTask: FamilyTask,
        currentUserRole: MembershipRole,
        assigneeDisplayName: String,
        scheduleViewModel: ScheduleViewModel
    ) {
        self.currentUserRole = currentUserRole
        self.assigneeDisplayNameFallback = assigneeDisplayName
        self.scheduleViewModel = scheduleViewModel
        _task = State(initialValue: initialTask)
    }

    /// 导航栏显示任务所属组织名（多组织场景下便于区分）。
    private var householdNavigationTitle: String {
        if let name = appRouter.selectableHouseholds.first(where: { $0.id == task.householdId })?.name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return trimmed
            }
        }
        return AppLocalized.string(L10n.Family.unnamedGroup, locale: locale)
    }

    private var detailScrollContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if task.source == .appleCalendar || task.source == .googleCalendar {
                externalSyncReadOnlyBanner
            }

            titleCard

            primaryDetailSettingsGroup

            if let statusError {
                Text(statusError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, bottomScrollPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.footnote)
    }

    var body: some View {
        ScrollView {
            detailScrollContent
        }
        .background(Color(.systemGroupedBackground))
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: TaskDetailNavigationWidthKey.self,
                    value: proxy.size.width
                )
            }
        }
        .onPreferenceChange(TaskDetailNavigationWidthKey.self) { navigationContentWidth = $0 }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 0) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .disabled(isUpdatingStatus || isDeletingTask)
                    .accessibilityLabel(L10n.Common.close)

                    Spacer(minLength: 12)

                    Text(householdNavigationTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(HouseholdColorStore.color(for: task.householdId))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)

                    Spacer(minLength: 12)

                    if canEditTask {
                        HStack(spacing: 14) {
                            if canShowEditButton {
                                Button {
                                    showingEditSheet = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.body.weight(.semibold))
                                }
                                .disabled(isUpdatingStatus || isDeletingTask)
                                .accessibilityLabel(L10n.Common.edit)
                            }

                            Button(role: .destructive) {
                                isShowingDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .disabled(isUpdatingStatus || isDeletingTask)
                            .accessibilityLabel(L10n.Schedule.deleteTask)
                        }
                    }
                }
                .frame(
                    width: navigationContentWidth > 16 ? navigationContentWidth - 16 : nil,
                    alignment: .center
                )
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if task.source.isReadOnly == false {
                statusMachineFooter
            }
        }
        .fullScreenCover(item: $attachmentGalleryPresentation) { presentation in
            TaskAttachmentImageGallery(
                attachments: taskDetailViewModel.attachments,
                startIndex: presentation.startIndex
            )
        }
        .sheet(isPresented: $showingEditSheet) {
            EditTaskView(
                task: task,
                familyProfiles: scheduleViewModel.familyProfiles,
                onUpdateSuccess: { updated in
                    task = updated
                    displayRecurrenceRule = nil
                    displayRecurrenceInterval = nil
                    Task {
                        await scheduleViewModel.loadTasks()
                        await loadForWhomProfiles()
                        await loadSeriesRecurrenceIfNeeded()
                        await taskDetailViewModel.loadAttachments(taskId: updated.id)
                    }
                },
                onAlarmSync: { updated in
                    scheduleViewModel.syncAlarms(for: updated)
                }
            )
            .environmentObject(appRouter)
        }
        .task(id: task.id) {
            await loadForWhomProfiles()
            await loadSeriesRecurrenceIfNeeded()
            await taskDetailViewModel.loadAttachments(taskId: task.id)
        }
        .alert(L10n.Schedule.deleteTask, isPresented: $isShowingDeleteAlert) {
            if task.seriesGrouping == nil {
                Button(L10n.Schedule.deleteThisTaskOnly, role: .destructive) {
                    Task { await performDelete(scope: .singleOnly) }
                }
            } else {
                Button(L10n.Schedule.deleteThisTaskOnly, role: .destructive) {
                    Task { await performDelete(scope: .singleOnly) }
                }
                Button(L10n.Schedule.deleteThisTaskAndLater, role: .destructive) {
                    Task { await performDelete(scope: .thisAndFuture) }
                }
            }
            Button(L10n.Common.cancel, role: .cancel) { }
        } message: {
            Text(task.seriesGrouping == nil ? L10n.Common.thisActionCannotBeUndone2.localized : L10n.Common.pleaseSelectAScopeToDelete.localized)
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, _ in
            Task {
                await loadForWhomProfiles()
            }
        }
    }

    // MARK: - Layout

    private var bottomScrollPadding: CGFloat {
        120
    }

    private var detailIconAccent: Color {
        HouseholdColorStore.color(for: task.householdId)
    }

    private var titleCard: some View {
        Text(scheduleViewModel.displayTitle(for: task))
            .font(.headline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .topLeading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
    }

    private var primaryDetailSettingsGroup: some View {
        VStack(spacing: 0) {
            CreateTaskFlatRow(
                systemImage: "calendar",
                title: householdNavigationTitle,
                iconColor: detailIconAccent
            ) {
                HouseholdColorDot(householdId: task.householdId, size: 14)
            }

            if showsDetailAttachments {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "paperclip",
                    title: AppLocalized.string(L10n.Common.attachments, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(attachmentsSummaryText)
                        .foregroundStyle(detailIconAccent)
                        .lineLimit(1)
                }
                detailAttachmentThumbnails
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
            }

            if task.isFlexibleTodo {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "flag",
                    title: AppLocalized.string(L10n.Common.dueBy, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(flexibleDeadlineDetailText)
                        .foregroundStyle(detailIconAccent)
                        .lineLimit(1)
                }
            } else {
                if task.isAllDay {
                    detailFlatDivider
                    CreateTaskFlatRow(
                        systemImage: "clock",
                        title: AppLocalized.string(L10n.Common.allDay, locale: locale),
                        iconColor: detailIconAccent
                    ) {
                        Text(AppLocalized.string(L10n.Common.yes, locale: locale))
                            .foregroundStyle(detailIconAccent)
                    }
                }

                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "calendar",
                    title: AppLocalized.string(L10n.Schedule.starts, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    detailDateTimeCapsules(for: scheduledAt, allDay: task.isAllDay)
                }

                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "calendar",
                    title: AppLocalized.string(L10n.Schedule.ends, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    if task.isAllDay {
                        Text(L10n.Common.allDay.localized)
                            .foregroundStyle(detailIconAccent)
                    } else if let end = plannedEndDate {
                        detailDateTimeCapsules(for: end, allDay: false)
                    } else {
                        Text(L10n.Common.none.localized)
                            .foregroundStyle(.secondary)
                    }
                }

                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "hourglass",
                    title: AppLocalized.string(L10n.Schedule.duration, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(TaskDurationFormatting.readableDuration(minutes: task.durationMinutes, locale: locale))
                        .foregroundStyle(detailIconAccent)
                }
            }

            if showsDetailColor {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "tag.fill",
                    title: AppLocalized.string(L10n.Schedule.taskColor, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Circle()
                        .fill(Color.taskCardCustomColor(fromHex: task.backgroundColor) ?? detailIconAccent)
                        .frame(width: 16, height: 16)
                }
            }

            if showsDetailReminder {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "alarm.fill",
                    title: AppLocalized.string(L10n.Schedule.remind, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    TaskReminderLabel.valueView(offsets: task.reminderOffsets)
                        .foregroundStyle(detailIconAccent)
                }
            }

            if showsDetailRepeat {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "repeat",
                    title: AppLocalized.string(L10n.Common.repeatLabel, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(inferredRecurrenceRule.titleKey)
                        .foregroundStyle(detailIconAccent)
                        .lineLimit(1)
                }
            }

            if showsDetailLocation {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "mappin.and.ellipse",
                    title: AppLocalized.string(L10n.Location.location, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(locationLine ?? "")
                        .foregroundStyle(detailIconAccent)
                        .lineLimit(1)
                }
            }

            if showsDetailMoreDetails {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "note.text",
                    title: AppLocalized.string(L10n.Common.moreDetails, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(descriptionMoreDetailsPart ?? "")
                        .foregroundStyle(detailIconAccent)
                        .lineLimit(2)
                }
            }

            if showsDetailAssignee {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "person.fill",
                    title: AppLocalized.string(L10n.Common.assignee, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    TaskAssigneeLabelView(
                        task: task,
                        members: scheduleViewModel.householdMembers,
                        profiles: scheduleViewModel.familyProfiles,
                        fallback: assigneeDisplayNameFallback
                    )
                    .foregroundStyle(detailIconAccent)
                    .lineLimit(1)
                }
            }

            if showsDetailForWhom {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "person.3",
                    title: AppLocalized.string(L10n.Common.forWhomFor, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(forWhomSummaryText)
                        .foregroundStyle(detailIconAccent)
                        .lineLimit(1)
                }
            }

            if showsDetailPriority {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "flag",
                    title: AppLocalized.string(L10n.Schedule.taskPriority2, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    Text(AppLocalized.string(L10n.Common.urgent, locale: locale))
                        .foregroundStyle(detailIconAccent)
                }
            }

            if showsDetailExpenses {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "banknote",
                    title: AppLocalized.string(L10n.Common.expenses, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    costValueView
                        .foregroundStyle(detailIconAccent)
                }
            }

            if showsDetailEmergency {
                detailFlatDivider
                CreateTaskFlatRow(
                    systemImage: "phone",
                    title: AppLocalized.string(L10n.Common.emergencyContactNumberMeetingLink, locale: locale),
                    iconColor: detailIconAccent
                ) {
                    emergencyTrailingValue
                }
            }

            detailFlatDivider
            CreateTaskFlatRow(
                systemImage: "tag",
                title: AppLocalized.string(L10n.Common.currentStatus, locale: locale),
                iconColor: detailIconAccent
            ) {
                Text(task.status.localizedName)
                    .foregroundStyle(task.status == .new ? Color.accentColor : detailIconAccent)
            }
        }
        .padding(.vertical, 6)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var showsDetailAttachments: Bool {
        taskDetailViewModel.attachments.isEmpty == false
    }

    private var showsDetailColor: Bool {
        Color.taskCardCustomColor(fromHex: task.backgroundColor) != nil
    }

    private var showsDetailReminder: Bool {
        guard let offsets = task.reminderOffsets else { return false }
        return offsets.isEmpty == false
    }

    private var showsDetailRepeat: Bool {
        inferredRecurrenceRule != .none
    }

    private var showsDetailLocation: Bool {
        locationLine != nil
    }

    private var showsDetailMoreDetails: Bool {
        descriptionMoreDetailsPart != nil
    }

    private var showsDetailAssignee: Bool {
        task.involvesWholeHousehold == false
            && (task.involvedMemberIds?.isEmpty == false)
    }

    private var showsDetailForWhom: Bool {
        isForWhomEveryone == false
    }

    private var showsDetailPriority: Bool {
        task.priority == .urgent || task.priority == .high
    }

    private var showsDetailExpenses: Bool {
        costIsEmpty == false
    }

    private var showsDetailEmergency: Bool {
        let trimmed = task.emergencyPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty == false
    }

    private var detailFlatDivider: some View {
        CreateTaskFlatDivider()
    }

    private var attachmentsSummaryText: String {
        let count = taskDetailViewModel.attachments.count
        if count == 0 {
            return AppLocalized.string(L10n.Common.none, locale: locale)
        }
        return "\(count)"
    }

    private var forWhomSummaryText: String {
        if isForWhomEveryone {
            return AppLocalized.string(L10n.Common.everyone, locale: locale)
        }
        let names = selectedForWhomProfiles.map(\.displayName)
        if names.isEmpty {
            return AppLocalized.string(L10n.Common.everyone, locale: locale)
        }
        return names.joined(separator: ", ")
    }

    @ViewBuilder
    private var emergencyTrailingValue: some View {
        let trimmed = task.emergencyPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            Text(L10n.Common.none.localized)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let url = dialOrWebURL(from: trimmed) {
            Text(trimmed)
                .foregroundStyle(detailIconAccent)
                .lineLimit(1)
                .underline()
                .onTapGesture { openURL(url) }
        } else {
            Text(trimmed)
                .foregroundStyle(detailIconAccent)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func detailDateTimeCapsules(for date: Date, allDay: Bool) -> some View {
        HStack(spacing: 4) {
            Text(
                date.formatted(
                    .dateTime.year().month(.abbreviated).day().locale(locale)
                )
            )
            .font(.footnote)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )

            if allDay == false {
                Text(ScheduleTimeFormatting.timelineClockTime(date, locale: locale))
                    .font(.footnote)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
        }
        .foregroundStyle(.primary)
    }

    private var detailAttachmentThumbnails: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(taskDetailViewModel.attachments.enumerated()), id: \.element.id) { index, attachment in
                    Button {
                        attachmentGalleryPresentation = AttachmentGalleryPresentation(startIndex: index)
                    } label: {
                        attachmentThumbnail(attachment)
                    }
                    .buttonStyle(.plain)
                    .disabled(attachment.displayImageURL == nil)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var externalSyncReadOnlyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.Schedule.syncedFromSystemCalendarEditable.localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .taskDetailFormCardStyled()
    }

    private var inferredRecurrenceRule: TaskRecurrenceRule {
        TaskRecurrenceRule.inferred(
            from: displayRecurrenceRule ?? task.recurrenceRule,
            recurrenceInterval: displayRecurrenceInterval ?? task.recurrenceInterval
        )
    }

    /// 子任务行上 `recurrence_*` 为空；展示时继承仍有效的母任务规则。
    private func loadSeriesRecurrenceIfNeeded() async {
        displayRecurrenceRule = nil
        displayRecurrenceInterval = nil

        #if canImport(Supabase)
        let householdId = appRouter.selectedHouseholdId ?? task.householdId
        let resolvedTask: FamilyTask
        if let fetched = try? await TaskSeriesSupabaseSupport.fetchTask(
            id: task.id,
            householdId: householdId
        ) {
            resolvedTask = fetched
            if fetched.recurrenceRule != task.recurrenceRule
                || fetched.recurrenceInterval != task.recurrenceInterval
                || fetched.parentTaskId != task.parentTaskId {
                task = fetched
            }
        } else {
            resolvedTask = task
        }

        if let rule = resolvedTask.recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines),
           rule.isEmpty == false {
            displayRecurrenceRule = resolvedTask.recurrenceRule
            displayRecurrenceInterval = resolvedTask.recurrenceInterval
            return
        }

        guard let parentId = resolvedTask.parentTaskId else {
            return
        }

        do {
            let parent = try await TaskSeriesSupabaseSupport.fetchTask(
                id: parentId,
                householdId: householdId
            )
            guard parent.isRecurringSeriesMother else { return }
            displayRecurrenceRule = parent.recurrenceRule
            displayRecurrenceInterval = parent.recurrenceInterval
        } catch {
            return
        }
        #else
        if let rule = task.recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines),
           rule.isEmpty == false {
            displayRecurrenceRule = task.recurrenceRule
            displayRecurrenceInterval = task.recurrenceInterval
        }
        #endif
    }

    // MARK: - 附件

    @ViewBuilder
    private func attachmentThumbnail(_ attachment: TaskAttachment) -> some View {
        if let url = attachment.displayImageURL {
            TaskAttachmentThumbnailView(url: url)
        } else {
            attachmentThumbnailPlaceholder(systemName: "photo")
        }
    }

    private func attachmentThumbnailPlaceholder(systemName: String) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(.tertiarySystemFill))
            .frame(width: 80, height: 80)
            .overlay {
                Image(systemName: systemName)
                    .foregroundStyle(.secondary)
            }
    }

    private var highlightedProfileIds: Set<UUID> {
        var s = Set<UUID>()
        if let single = task.targetProfileId {
            s.insert(single)
        }
        if let multi = task.targetProfileIds {
            multi.forEach { s.insert($0) }
        }
        return s
    }

    private var isForWhomEveryone: Bool {
        highlightedProfileIds.isEmpty
    }

    private var selectedForWhomProfiles: [FamilyProfile] {
        guard isForWhomEveryone == false else { return [] }
        let profileById = Dictionary(uniqueKeysWithValues: forWhomProfiles.map { ($0.id, $0) })
        let orderedIds: [UUID]
        if let multi = task.targetProfileIds, multi.isEmpty == false {
            orderedIds = multi
        } else if let single = task.targetProfileId {
            orderedIds = [single]
        } else {
            orderedIds = []
        }
        return orderedIds.compactMap { profileById[$0] }
    }


    /// 与新建任务表单一致：`更多细节` 与 `财务详细说明` 以双换行拼在 `description`。
    private var descriptionParts: (more: String?, finance: String?) {
        let raw = task.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if raw.isEmpty { return (nil, nil) }
        let parts = raw.components(separatedBy: "\n\n")
        if parts.count >= 2 {
            let head = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let tail = parts.dropFirst().joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            return (head.isEmpty ? nil : head, tail.isEmpty ? nil : tail)
        }
        return (raw, nil)
    }

    private var descriptionMoreDetailsPart: String? {
        descriptionParts.more
    }

    private var descriptionFinancePart: String? {
        descriptionParts.finance
    }

    private var financeCostIsPlaceholder: Bool {
        costIsEmpty
    }

    private func dialOrWebURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }
        let collapsed = trimmed.filter { !$0.isWhitespace && !$0.isNewline }
        let digits = collapsed.filter { $0.isNumber || $0 == "+" }
        guard digits.isEmpty == false else { return nil }
        return URL(string: "tel:\(digits)")
    }

    // MARK: - 属性格式化

    private var timePlanningStartText: String {
        let start = scheduledAt
        if task.isAllDay {
            return start.formatted(
                .dateTime
                    .month(.defaultDigits)
                    .day(.defaultDigits)
                    .weekday(.wide)
                    .locale(locale)
            )
        }
        return ScheduleTimeFormatting.timelineClockTime(start, locale: locale)
    }

    private var timePlanningEndText: String? {
        guard let end = plannedEndDate else { return nil }
        if task.isAllDay {
            return end.formatted(
                .dateTime
                    .month(.defaultDigits)
                    .day(.defaultDigits)
                    .weekday(.wide)
                    .locale(locale)
            )
        }
        return ScheduleTimeFormatting.timelineClockTime(end, locale: locale)
    }

    private var plannedEndDate: Date? {
        if task.isFlexibleTodo {
            return task.endDatetime
        }
        return task.timelineEndDate
    }

    private var flexibleDeadlineDetailText: String {
        let day = task.flexibleDeadlineDay ?? task.endDatetime ?? task.createdAt
        return day.formatted(
            .dateTime
                .month(.defaultDigits)
                .day(.defaultDigits)
                .weekday(.wide)
                .locale(locale)
        )
    }

    private var scheduledAt: Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private var costIsEmpty: Bool {
        guard let minor = task.estimatedCost else { return true }
        return minor == 0
    }

    @ViewBuilder
    private var costValueView: some View {
        if costIsEmpty {
            Text(L10n.Common.none.localized)
        } else if let minor = task.estimatedCost {
            Text(verbatim: formattedCostAmount(minorUnits: minor))
        } else {
            Text(L10n.Common.none.localized)
        }
    }

    private func formattedCostAmount(minorUnits: Int) -> String {
        let value = Double(minorUnits) / 100.0
        let symbol = locale.currencySymbol ?? Locale.current.currencySymbol ?? "¥"
        if value == floor(value) {
            return String(format: "%@%.0f", symbol, value)
        }
        return String(format: "%@%.1f", symbol, value)
    }

    private var locationLine: String? {
        let name = task.locationData?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let address = task.locationData?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, name.isEmpty == false, let address, address.isEmpty == false, name != address {
            return "\(name) · \(address)"
        }
        if let name, name.isEmpty == false { return name }
        if let address, address.isEmpty == false { return address }
        return nil
    }

    // MARK: - 数据加载

    @MainActor
    private func loadForWhomProfiles() async {
        if scheduleViewModel.familyProfiles.isEmpty == false {
            forWhomProfiles = scheduleViewModel.familyProfiles
            return
        }

        let householdId = appRouter.selectedHouseholdId ?? task.householdId
        #if canImport(Supabase)
        do {
            let roster = try await SupabaseHouseholdRosterLoader.fetch(
                in: householdId,
                client: SupabaseManager.shared.client
            )
            forWhomProfiles = roster.profiles
        } catch {
            forWhomProfiles = []
        }
        #else
        forWhomProfiles = []
        #endif
    }

    private var canEditTask: Bool {
        guard task.source.isReadOnly == false else { return false }

        // `tasks.creator_id` 存的是 household_memberships.id，须与当前上下文 membership 比较，禁止用 auth user id。
        let isTaskCreator = appRouter.selectedMembershipId == task.creatorId

        let isGroupAdmin: Bool
        switch currentUserRole {
        case .admin, .creator:
            isGroupAdmin = true
        case .member:
            isGroupAdmin = false
        }

        return isTaskCreator || isGroupAdmin
    }

    /// 已完成任务按历史只读处理，不展示编辑入口（删除仍可由管理员操作）。
    private var canShowEditButton: Bool {
        canEditTask && task.status != .completed
    }

    // MARK: - 底部状态机

    private func statusFooterPrimaryButton(
        _ title: LocalizedStringResource,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .disabled(isUpdatingStatus)
    }

    private var statusMachineFooter: some View {
        VStack(spacing: 0) {
            Group {
                switch task.status {
                case .new:
                    if task.isFlexibleTodo {
                        statusFooterPrimaryButton(L10n.Schedule.completeTheTask.localized, tint: .green) {
                            Task { await updateTaskStatus(to: .completed) }
                        }
                    } else {
                        statusFooterPrimaryButton(L10n.Schedule.acceptTask.localized, tint: .orange) {
                            Task { await updateTaskStatus(to: .accepted) }
                        }
                    }

                case .accepted:
                    statusFooterPrimaryButton(L10n.Schedule.completeTheTask.localized, tint: .green) {
                        Task { await updateTaskStatus(to: .completed) }
                    }

                case .inProgress:
                    statusFooterPrimaryButton(L10n.Common.markAsComplete.localized, tint: .green) {
                        Task { await updateTaskStatus(to: .completed) }
                    }

                case .completed:
                    completedStatusFooter

                default:
                    Text(L10n.Schedule.thisTaskHasBeenCompleted.localized)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [
                        Color(.systemGroupedBackground).opacity(0),
                        Color(.systemBackground).opacity(0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay {
            if isUpdatingStatus || isDeletingTask {
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                    ProgressView()
                        .scaleEffect(1.08)
                }
                .allowsHitTesting(true)
            }
        }
    }

    private var completedStatusFooter: some View {
        HStack(alignment: .center, spacing: 12) {
            if task.source.isReadOnly == false {
                Button {
                    Task { await updateTaskStatus(to: .new) }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingStatus)
                .accessibilityLabel(L10n.Common.markAsToDoAgain.localized)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }

            Text(L10n.Schedule.thisTaskHasBeenCompleted.localized)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func updateTaskStatus(to newStatus: TaskStatus) async {
        guard isUpdatingStatus == false else { return }
        isUpdatingStatus = true
        statusError = nil
        defer { isUpdatingStatus = false }

        do {
            let previousStatus = task.status
            let completionLocation: TaskCompletionLocation?
            if newStatus == .completed, let membershipId = appRouter.selectedMembershipId {
                completionLocation = await TaskCompletionLocationProvider.currentSnapshot(
                    completedBy: membershipId
                )
            } else {
                completionLocation = nil
            }
            let updated = try await scheduleViewModel.patchTaskStatus(
                taskId: task.id,
                to: newStatus,
                completionLocation: completionLocation,
                actingMembershipId: appRouter.selectedMembershipId
            )
            task = updated
            if newStatus == .accepted {
                ReviewRedirectManager.shared.checkAndTriggerAlert(for: .taskAcceptance)
            }
            if newStatus == .completed {
                AnalyticsManager.log(event: .taskCompleted(taskId: task.id))
                ReviewRedirectManager.shared.checkAndTriggerAlert(for: .firstCompletion)
            }
            if previousStatus == .completed || newStatus == .completed {
                NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            }
            await loadForWhomProfiles()
        } catch {
            statusError = error.localizedDescription
        }
    }

    private func performDelete(scope: RecurringDeleteScope) async {
        guard isDeletingTask == false else { return }
        isDeletingTask = true
        statusError = nil
        defer { isDeletingTask = false }
        #if canImport(Supabase)
        do {
            switch scope {
            case .singleOnly:
                await scheduleViewModel.deleteTask(taskId: task.id)
            case .thisAndFuture:
                guard let grouping = task.seriesGrouping else {
                    statusError = AppLocalized.string(L10n.Schedule.couldNotResolveTheRecurringSeriesGroupBul, locale: locale)
                    return
                }
                let cutoff = task.dueDate ?? .distantPast
                let rows = try await TaskSeriesSupabaseSupport.fetchSeriesTasks(
                    householdId: task.householdId,
                    grouping: grouping,
                    dueOnOrAfter: cutoff
                )
                let ids = rows.map(\.id)
                for id in ids {
                    await NotificationManager.shared.cancelAllPending(for: id)
                }
                try await TaskSeriesSupabaseSupport.deleteTasks(ids: ids)
                await scheduleViewModel.loadTasks()
            }
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            dismiss()
        } catch {
            statusError = String(
                format: L10n.Common.deleteFailed.string(locale: locale),
                error.localizedDescription
            )
        }
        #else
        _ = scope
        statusError = L10n.Common.supabaseSdkIsNotAvailableInThisBuild.string(locale: locale)
        #endif
    }
}

private struct AttachmentGalleryPresentation: Identifiable {
    let id = UUID()
    let startIndex: Int
}

private struct TaskDetailNavigationWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview("成员 · 待接受") {
    NavigationStack {
        TaskDetailView(
            initialTask: FamilyTask.mockTasks[1],
            currentUserRole: .member,
            assigneeDisplayName: "奶奶",
            scheduleViewModel: AppViewModels.makeScheduleViewModel()
        )
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environment(\.locale, Locale(identifier: "en"))
    }
}

#Preview("管理员 · 已完成") {
    NavigationStack {
        TaskDetailView(
            initialTask: FamilyTask.mockTasks[0],
            currentUserRole: .admin,
            assigneeDisplayName: "爷爷",
            scheduleViewModel: AppViewModels.makeScheduleViewModel()
        )
        .environmentObject(AppRouter())
        .environmentObject(AppSettingsManager.shared)
        .environment(\.locale, Locale(identifier: "en"))
    }
}
