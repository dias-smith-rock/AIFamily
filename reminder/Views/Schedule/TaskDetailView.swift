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

struct TaskDetailView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.locale) private var locale
    @Environment(\.isGuestMode) private var isGuestMode
    @ObservedObject private var scheduleViewModel: ScheduleViewModel
    @StateObject private var taskDetailViewModel = TaskDetailViewModel()

    private let currentUserRole: MembershipRole
    private let assigneeDisplayNameFallback: String

    @State private var task: FamilyTask
    @State private var showMoreOptions = false
    @State private var showingEditSheet = false
    @State private var isUpdatingStatus = false
    @State private var isDeletingTask = false
    @State private var statusError: String?
    @State private var forWhomProfiles: [FamilyProfile] = []
    @State private var displayRecurrenceRule: String?
    @State private var displayRecurrenceInterval: Int?
    @State private var isShowingDeleteAlert = false
    @State private var showGuestSignInRequiredAlert = false
    @State private var attachmentGalleryPresentation: AttachmentGalleryPresentation?
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

    private var detailScrollContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            if task.source.isReadOnly {
                externalSyncReadOnlyBanner
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            titleHeader
                .padding(.horizontal, 20)
                .padding(.top, 4)

            timePlanningCard
                .padding(.horizontal, 16)
                .padding(.top, 16)

            forWhomSection
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if taskDetailViewModel.attachments.isEmpty == false {
                attachmentsSection
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
            }

            coreInfoCard
                .padding(.horizontal, 16)
                .padding(.top, 16)

            if showMoreOptions == false {
                expandMoreControl
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
            }

            if showMoreOptions {
                expandedReadonlySection
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                collapseMoreControl
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            if let statusError {
                Text(statusError)
                    .font(AppTheme.FontToken.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }
        }
        .padding(.bottom, bottomScrollPadding)
    }

    var body: some View {
        ScrollView {
            detailScrollContent
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(L10n.Schedule.missionDetails.localized)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.Common.close.localized) {
                    dismiss()
                }
                .fontWeight(.medium)
                .disabled(isUpdatingStatus || isDeletingTask)
            }
            if canEditTask {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if canShowEditButton {
                            Button {
                                showingEditSheet = true
                            } label: {
                                Text(L10n.Common.edit.localized)
                                    .fontWeight(.semibold)
                            }
                            .disabled(isUpdatingStatus || isDeletingTask)
                        }

                        Button(role: .destructive) {
                            isShowingDeleteAlert = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .disabled(isUpdatingStatus || isDeletingTask)
                    }
                }
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
        .guestSignInRequiredAlert(isPresented: $showGuestSignInRequiredAlert)
    }

    // MARK: - Layout

    private var bottomScrollPadding: CGFloat {
        120
    }

    private var titleHeader: some View {
        Text(scheduleViewModel.displayTitle(for: task))
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var externalSyncReadOnlyBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "calendar.badge.lock")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(L10n.Schedule.thisScheduleIsSynchronizedExternallyAndDoe.localized)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - 核心信息卡片（始终）

    private var coreInfoCard: some View {
        VStack(spacing: 0) {
            TaskDetailRowView(systemImage: "repeat", label: L10n.Common.repeat2) {
                Text(inferredRecurrenceRule.titleKey)
            }
            cardDivider
            TaskDetailRowView(systemImage: "bell", label: L10n.Schedule.remind) {
                TaskReminderLabel.valueView(offsets: task.reminderOffsets)
            }
            cardDivider
            TaskDetailRowView(systemImage: "person", label: L10n.Common.assignee) {
                TaskAssigneeLabelView(
                    task: task,
                    members: scheduleViewModel.householdMembers,
                    profiles: scheduleViewModel.familyProfiles,
                    fallback: assigneeDisplayNameFallback
                )
            }
            cardDivider
            TaskDetailRowView(
                systemImage: "banknote",
                label: L10n.Common.expenses,
                valueIsPlaceholder: costIsEmpty
            ) {
                costValueView
            }
            cardDivider
            TaskDetailRowView(
                systemImage: "tag",
                label: L10n.Common.currentStatus,
                valueAccent: task.status == .new
            ) {
                Text(task.status.localizedName)
            }
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
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

        if isGuestMode {
            if let rule = task.recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines),
               rule.isEmpty == false {
                displayRecurrenceRule = task.recurrenceRule
                displayRecurrenceInterval = task.recurrenceInterval
            }
            return
        }

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

    private var timePlanningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.Common.time.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if task.isFlexibleTodo {
                    timePlanningLine(label: L10n.Common.dueDate.localized) {
                        Text(flexibleDeadlineDetailText)
                    }
                    Text(L10n.Common.canBeCompletedAnytimeBeforeThisDate.localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if task.isAllDay {
                    timePlanningLine(label: L10n.Common.time2.localized) {
                        Text(L10n.Common.allDay.localized)
                    }
                } else {
                    timePlanningLine(label: L10n.Common.startTime.localized) {
                        Text(timePlanningStartText)
                    }
                    if let endText = timePlanningEndText {
                        timePlanningLine(label: L10n.Common.endTime.localized) {
                            Text(endText)
                        }
                    }
                    timePlanningLine(label: L10n.Common.totalDuration.localized) {
                        TaskDurationText(minutes: task.durationMinutes)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private func timePlanningLine<Content: View>(
        label: LocalizedStringKey,
        @ViewBuilder value: () -> Content
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(Text(label)):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            value()
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var cardDivider: some View {
        Divider()
            .padding(.leading, 50)
    }

    // MARK: - 附件

    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "paperclip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.Common.attachments.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(taskDetailViewModel.attachments.enumerated()), id: \.element.id) { index, attachment in
                        Button {
                            attachmentGalleryPresentation = AttachmentGalleryPresentation(startIndex: index)
                        } label: {
                            attachmentThumbnail(attachment)
                        }
                        .buttonStyle(.plain)
                        .disabled(attachment.displayImageURL == nil)
                        .accessibilityLabel(L10n.Common.viewAttachment.localized)
                        .accessibilityHint(L10n.Common.doubleTapForFullScreenSwipeLeftOrRightT.localized)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

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

    // MARK: - 为了谁（纯展示）

    private var forWhomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(L10n.Common.forLabel.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    if isForWhomEveryone {
                        forWhomEveryoneChip
                    } else {
                        ForEach(selectedForWhomProfiles) { profile in
                            forWhomProfileChip(profile: profile, selected: true)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private var forWhomEveryoneChip: some View {
        let selected = isForWhomEveryone
        return VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(selected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill))
                    .frame(width: 52, height: 52)
                Image(systemName: "person.3.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 18, y: 18)
                }
            }
            .frame(width: 60, height: 60)
            Text(L10n.Common.everyone.localized)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Family.forWhomAllMembers.localized)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func forWhomProfileChip(profile: FamilyProfile, selected: Bool) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 52, height: 52)

                if let urlString = profile.avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let url = URL(string: urlString), urlString.isEmpty == false {
                    KFImage(url)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else {
                    Text(profileInitials(profile.displayName))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }

                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .offset(x: 18, y: 18)
                }
            }
            .frame(width: 60, height: 60)
            .overlay {
                Circle()
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2.5)
                    .frame(width: 56, height: 56)
            }

            Text(profile.displayName)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func profileInitials(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = t.first else { return "?" }
        return String(c).uppercased()
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

    // MARK: - 渐进展开

    private var expandMoreControl: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                showMoreOptions = true
            }
        } label: {
            HStack(spacing: 6) {
                Text(L10n.Common.showMoreOptions.localized)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "˅")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private var collapseMoreControl: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                showMoreOptions = false
            }
        } label: {
            HStack(spacing: 6) {
                Text(L10n.Common.collapseMoreOptions.localized)
                    .font(.subheadline.weight(.semibold))
                Text(verbatim: "˄")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 展开区（只读，对齐设计稿）

    private var expandedReadonlySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            expandedCard(title: L10n.Schedule.taskPriority.localized) {
                priorityReadonlySegmentVisual
            }

            expandedCard(title: L10n.Common.emergencyContactNumberMeetingLink.localized) {
                emergencyReadonlyBlock
            }

            expandedCard(title: L10n.Location.location.localized) {
                locationReadonlyRow
            }

            expandedCard(title: L10n.Common.moreDetails.localized) {
                readonlyMultilineBlock(
                    text: descriptionMoreDetailsPart,
                    emptyPlaceholder: L10n.Common.noNotesYet.localized
                )
            }

            expandedCard(title: L10n.Common.financeAndNotes.localized) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L10n.Common.expenses.localized)
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        costValueView
                            .font(.body.weight(.medium))
                            .foregroundStyle(financeCostIsPlaceholder ? .tertiary : .primary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.Common.detailedDescription.localized)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        readonlyMultilineBlock(
                            text: descriptionFinancePart,
                            emptyPlaceholder: L10n.Common.youCanFillInExpenseDetailsPaymentMethods.localized,
                            emptyAsCaptionHint: true
                        )
                    }
                }
            }
        }
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

    /// 只读分段外观（非 `Picker`）：展示当前优先级对应选中态。
    private var priorityReadonlySegmentVisual: some View {
        let isUrgent = (task.priority == .urgent || task.priority == .high)
        return HStack(spacing: 0) {
            Text(L10n.Common.urgent.localized)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isUrgent ? Color.accentColor : Color.secondary)
                .background(isUrgent ? Color.accentColor.opacity(0.18) : Color.clear)

            Text(L10n.Common.generally.localized)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isUrgent ? Color.secondary : Color.accentColor)
                .background(isUrgent ? Color.clear : Color.accentColor.opacity(0.18))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Schedule.taskPriority.localized)
        .accessibilityValue(task.priority.localizedName)
    }

    private var emergencyReadonlyBlock: some View {
        let trimmed = task.emergencyPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if trimmed.isEmpty {
                    Text(L10n.Common.none.localized)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    emergencyReadonlyContent(trimmed)
                }
            }
            Image(systemName: "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(trimmed.isEmpty ? Color.secondary.opacity(0.35) : Color.accentColor)
                .accessibilityHidden(true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var locationReadonlyRow: some View {
        let has = locationLine != nil
        return HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
            Group {
                if has, let line = locationLine {
                    Text(verbatim: line)
                } else {
                    Text(L10n.Location.locationNotAdded.localized)
                }
            }
                .font(.body)
                .foregroundStyle(has ? .primary : .tertiary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func readonlyMultilineBlock(
        text: String?,
        emptyPlaceholder: LocalizedStringKey,
        emptyAsCaptionHint: Bool = false
    ) -> some View {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            Text(emptyPlaceholder)
                .font(emptyAsCaptionHint ? .subheadline : .body)
                .italic(emptyAsCaptionHint == false)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .frame(minHeight: emptyAsCaptionHint ? 72 : 88, alignment: .topLeading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            Text(trimmed)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .frame(minHeight: 88, alignment: .topLeading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func expandedCard<Content: View>(title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    @ViewBuilder
    private func emergencyReadonlyContent(_ raw: String) -> some View {
        if let url = dialOrWebURL(from: raw) {
            Text(raw)
                .font(.body)
                .foregroundStyle(.tint)
                .underline()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    openURL(url)
                }
                .accessibilityHint(L10n.Common.doubleTapToCallOrOpenTheLink.localized)
        } else {
            Text(raw)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        _ title: LocalizedStringKey,
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
        if isGuestMode {
            switch scope {
            case .singleOnly:
                await scheduleViewModel.deleteTask(taskId: task.id)
            case .thisAndFuture:
                await performGuestSeriesDelete()
            }
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            dismiss()
            return
        }
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

    private func performGuestSeriesDelete() async {
        guard let grouping = task.seriesGrouping else {
            statusError = AppLocalized.string(L10n.Schedule.couldNotResolveTheRecurringSeriesGroupBul, locale: locale)
            return
        }
        let cutoff = task.dueDate ?? .distantPast
        let householdId = task.householdId
        let ids = scheduleViewModel.tasks.filter { candidate in
            guard candidate.householdId == householdId else { return false }
            let anchor = candidate.dueDate ?? candidate.createdAt
            guard anchor >= cutoff else { return false }
            switch grouping {
            case .byParentRoot(let rootId):
                return candidate.id == rootId || candidate.parentTaskId == rootId
            case .byLegacyGroup(let groupId):
                return candidate.groupId == groupId
            }
        }.map(\.id)
        for id in ids {
            await scheduleViewModel.deleteTask(taskId: id)
        }
    }
}

private struct AttachmentGalleryPresentation: Identifiable {
    let id = UUID()
    let startIndex: Int
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
