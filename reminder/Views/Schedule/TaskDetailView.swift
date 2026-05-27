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
    @ObservedObject private var scheduleViewModel: ScheduleViewModel

    private let currentUserRole: MembershipRole
    private let assigneeDisplayNameFallback: String

    @State private var task: FamilyTask
    @State private var showMoreOptions = false
    @State private var showingEditSheet = false
    @State private var isUpdatingStatus = false
    @State private var isDeletingTask = false
    @State private var statusError: String?
    @State private var assigneeLine: String
    @State private var forWhomProfiles: [FamilyProfile] = []
    @State private var isShowingDeleteScopeDialog = false
    @State private var showCompletedReminderCleanupAlert = false

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
        _assigneeLine = State(initialValue: assigneeDisplayName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if task.source.isReadOnly {
                    externalSyncReadOnlyBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                titleHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                coreInfoCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                timePlanningCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                forWhomSection
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
        .background(Color(.systemGroupedBackground))
        .navigationTitle(localized("任务详情"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(localized("关闭")) {
                    dismiss()
                }
                .fontWeight(.medium)
                .disabled(isUpdatingStatus || isDeletingTask)
            }
            if canEditTask {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        Button {
                            showingEditSheet = true
                        } label: {
                            Text(localized("编辑"))
                                .fontWeight(.semibold)
                        }
                        .disabled(isUpdatingStatus || isDeletingTask)

                        Button(role: .destructive) {
                            isShowingDeleteScopeDialog = true
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
        .sheet(isPresented: $showingEditSheet) {
            EditTaskView(
                task: task,
                onUpdateSuccess: { updated in
                    task = updated
                    Task {
                        await scheduleViewModel.loadTasks()
                        await refreshAssigneeLine()
                        await loadForWhomProfiles()
                    }
                },
                onAlarmSync: { updated in
                    scheduleViewModel.syncAlarms(for: updated)
                }
            )
            .environmentObject(appRouter)
            .presentationDragIndicator(.visible)
        }
        .task(id: task.id) {
            await refreshAssigneeLine()
            await loadForWhomProfiles()
        }
        .confirmationDialog(
            localized("删除任务"),
            isPresented: $isShowingDeleteScopeDialog,
            titleVisibility: .visible
        ) {
            if task.seriesGrouping == nil {
                Button(localized("仅删除此任务"), role: .destructive) {
                    Task { await performDelete(scope: .singleOnly) }
                }
            } else {
                Button(localized("仅删除此任务"), role: .destructive) {
                    Task { await performDelete(scope: .singleOnly) }
                }
                Button(localized("删除此任务及以后"), role: .destructive) {
                    Task { await performDelete(scope: .thisAndFuture) }
                }
            }
            Button(localized("取消"), role: .cancel) { }
        } message: {
            Text(localized(task.seriesGrouping == nil ? "此操作不可撤销。" : "请选择删除范围。"))
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, _ in
            Task {
                await refreshAssigneeLine()
                await loadForWhomProfiles()
            }
        }
    }

    // MARK: - Layout

    private var bottomScrollPadding: CGFloat {
        120
    }

    private var titleHeader: some View {
        Text(task.title)
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
            Text(TaskDetailCopy.externalSyncReadOnlyBanner(locale: locale))
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
            coreRow(systemImage: "repeat", label: localized("重复"), value: repeatDisplayText)
            cardDivider
            coreRow(systemImage: "bell", label: localized("提醒"), value: reminderDisplayText)
            cardDivider
            coreRow(systemImage: "person", label: localized("谁去办 (Assignee)"), value: assigneeLine)
            cardDivider
            coreRow(systemImage: "banknote", label: localized("预计开销"), value: costDisplayText, valueIsPlaceholder: costIsEmpty)
            cardDivider
            coreRow(
                systemImage: "tag",
                label: localized("当前状态"),
                value: statusFriendlyLabel,
                valueAccent: task.status == .new
            )
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private var timePlanningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(localized("时间规划"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                timePlanningLine(label: localized("开始时间"), value: timePlanningStartText)
                if let endText = timePlanningEndText {
                    timePlanningLine(label: localized("结束时间"), value: endText)
                }
                timePlanningLine(
                    label: localized("总花费时间"),
                    value: TaskDurationFormatting.readableDuration(minutes: task.durationMinutes, locale: locale)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }

    private func timePlanningLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(label):")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
    }

    private var cardDivider: some View {
        Divider()
            .padding(.leading, 50)
    }

    private func coreRow(
        systemImage: String,
        label: String,
        value: String,
        valueIsPlaceholder: Bool = false,
        valueAccent: Bool = false
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.tertiary)
                .frame(width: 22, alignment: .center)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 12)

            Text(value)
                .font(.body.weight(.medium))
                .foregroundStyle(coreValueForeground(isPlaceholder: valueIsPlaceholder, accent: valueAccent))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    private func coreValueForeground(isPlaceholder: Bool, accent: Bool) -> Color {
        if isPlaceholder {
            return Color.secondary.opacity(0.75)
        }
        if accent {
            return Color.accentColor
        }
        return Color.primary
    }

    // MARK: - 为了谁（纯展示）

    private var forWhomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(localized("为了谁"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    forWhomEveryoneChip
                    ForEach(forWhomProfiles) { profile in
                        forWhomProfileChip(profile: profile, selected: isProfileHighlighted(profile.id))
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
            Text(localized("所有人"))
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(localized("为了谁：全体成员"))
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

    private func isProfileHighlighted(_ id: UUID) -> Bool {
        highlightedProfileIds.contains(id)
    }

    // MARK: - 渐进展开

    private var expandMoreControl: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                showMoreOptions = true
            }
        } label: {
            HStack(spacing: 6) {
                Text(localized("显示更多选项"))
                    .font(.subheadline.weight(.semibold))
                Text("˅")
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
                Text(localized("收起更多选项"))
                    .font(.subheadline.weight(.semibold))
                Text("˄")
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
            expandedCard(title: localized("任务优先级")) {
                priorityReadonlySegmentVisual
            }

            expandedCard(title: localized("紧急联系号码 / 会议链接")) {
                emergencyReadonlyBlock
            }

            expandedCard(title: localized("地理位置")) {
                locationReadonlyRow
            }

            expandedCard(title: localized("更多细节")) {
                readonlyMultilineBlock(
                    text: descriptionMoreDetailsPart,
                    emptyPlaceholder: localized("暂无备注")
                )
            }

            expandedCard(title: localized("财务与备注")) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(localized("预计开销"))
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Text(financeCostLineText)
                            .font(.body.weight(.medium))
                            .foregroundStyle(financeCostIsPlaceholder ? .tertiary : .primary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(localized("详细说明"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        readonlyMultilineBlock(
                            text: descriptionFinancePart,
                            emptyPlaceholder: localized("可填写开支明细、支付方式等…"),
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

    private var financeCostLineText: String {
        costDisplayText
    }

    /// 只读分段外观（非 `Picker`）：展示当前优先级对应选中态。
    private var priorityReadonlySegmentVisual: some View {
        let isUrgent = (task.priority == .urgent || task.priority == .high)
        return HStack(spacing: 0) {
            Text(localized("紧急"))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isUrgent ? Color.accentColor : Color.secondary)
                .background(isUrgent ? Color.accentColor.opacity(0.18) : Color.clear)

            Text(localized("一般"))
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isUrgent ? Color.secondary : Color.accentColor)
                .background(isUrgent ? Color.clear : Color.accentColor.opacity(0.18))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(localized("任务优先级")): \(priorityReadonlyText)")
    }

    private var emergencyReadonlyBlock: some View {
        let trimmed = task.emergencyPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if trimmed.isEmpty {
                    Text(localized("无"))
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
            Text(has ? (locationLine ?? "") : localized("尚未添加位置"))
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
        emptyPlaceholder: String,
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

    private func expandedCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
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

    private var priorityReadonlyText: String {
        switch task.priority {
        case .urgent, .high:
            return TaskDetailCopy.priorityUrgent(locale: locale)
        case .normal, .low:
            return TaskDetailCopy.priorityNormal(locale: locale)
        @unknown default:
            return TaskDetailCopy.priorityNormal(locale: locale)
        }
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
                .accessibilityHint(TaskDetailCopy.tapToCallOrOpenLink(locale: locale))
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
        return start.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(locale)
        )
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
        return end.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
                .locale(locale)
        )
    }

    private var plannedEndDate: Date? {
        Calendar.current.date(byAdding: .minute, value: task.durationMinutes, to: scheduledAt)
    }

    private var scheduledAt: Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private var repeatDisplayText: String {
        guard let rule = task.recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines),
              rule.isEmpty == false else {
            return TaskDetailCopy.repeatNever(locale: locale)
        }
        if rule.uppercased().contains("DAILY") { return TaskDetailCopy.repeatDaily(locale: locale) }
        if rule.uppercased().contains("WEEKLY") { return TaskDetailCopy.repeatWeekly(locale: locale) }
        if rule.uppercased().contains("MONTHLY") { return TaskDetailCopy.repeatMonthly(locale: locale) }
        return TaskDetailCopy.repeatCustom(locale: locale)
    }

    private var reminderDisplayText: String {
        guard let offsets = task.reminderOffsets, offsets.isEmpty == false else {
            return TaskDetailCopy.none(locale: locale)
        }
        return offsets.sorted().map(reminderLabel(forMinutes:)).joined(separator: TaskDetailCopy.listSeparator(locale: locale))
    }

    private func reminderLabel(forMinutes m: Int) -> String {
        switch m {
        case 0: return TaskDetailCopy.reminderOnTime(locale: locale)
        case 5: return TaskDetailCopy.reminder5Min(locale: locale)
        case 10: return TaskDetailCopy.reminder10Min(locale: locale)
        case 15: return TaskDetailCopy.reminder15Min(locale: locale)
        case 30: return TaskDetailCopy.reminder30Min(locale: locale)
        case 60: return TaskDetailCopy.reminder1Hour(locale: locale)
        default: return String(format: TaskDetailCopy.reminderMinutesBeforeFormat(locale: locale), m)
        }
    }

    private var costIsEmpty: Bool {
        guard let minor = task.estimatedCost else { return true }
        return minor == 0
    }

    private var costDisplayText: String {
        guard let minor = task.estimatedCost else { return TaskDetailCopy.none(locale: locale) }
        if minor == 0 { return TaskDetailCopy.none(locale: locale) }
        let value = Double(minor) / 100.0
        let symbol = Locale.current.currencySymbol ?? "¥"
        if value == floor(value) {
            return String(format: "%@%.0f", symbol, value)
        }
        return String(format: "%@%.1f", symbol, value)
    }

    private var statusFriendlyLabel: String {
        switch task.status {
        case .new: return TaskDetailCopy.statusPendingAcceptance(locale: locale)
        case .accepted: return TaskDetailCopy.statusAccepted(locale: locale)
        case .inProgress: return TaskDetailCopy.statusInProgress(locale: locale)
        case .completed: return TaskDetailCopy.statusCompleted(locale: locale)
        case .issue: return TaskDetailCopy.statusIssue(locale: locale)
        case .failed: return TaskDetailCopy.statusFailed(locale: locale)
        case .expired: return TaskDetailCopy.statusExpired(locale: locale)
        case .cancelled: return TaskDetailCopy.statusCancelled(locale: locale)
        }
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
    private func refreshAssigneeLine() async {
        assigneeLine = scheduleViewModel.assigneeLabel(for: task, locale: locale)
    }

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
        switch currentUserRole {
        case .admin, .creator: return true
        case .member: return false
        }
    }

    // MARK: - 底部状态机

    private var statusMachineFooter: some View {
        VStack(spacing: 0) {
            Group {
                switch task.status {
                case .new:
                    Button {
                        Task { await updateTaskStatus(to: .accepted) }
                    } label: {
                        Text(localized("接受任务"))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(isUpdatingStatus)

                case .accepted:
                    VStack(spacing: 12) {
                        Button {
                            Task { await updateTaskStatus(to: .completed) }
                        } label: {
                            Text(localized("完成任务"))
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .controlSize(.large)
                        .disabled(isUpdatingStatus)

                        Button {
                            Task { await updateTaskStatus(to: .issue) }
                        } label: {
                            Text(localized("遇到问题"))
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isUpdatingStatus)
                    }

                case .inProgress:
                    Button {
                        Task { await updateTaskStatus(to: .completed) }
                    } label: {
                        Text(localized("标记为完成"))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .disabled(isUpdatingStatus)

                default:
                    Text(localized("✅ 该任务已完结"))
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
        .alert(localized("任务已完成"), isPresented: $showCompletedReminderCleanupAlert) {
            Button(localized("是")) {
                Task {
                    await NotificationManager.shared.cancelAllPending(for: task.id)
                }
            }
            Button(localized("否"), role: .cancel) {}
        } message: {
            Text(localized("是否需要为您删除对应的闹钟提醒？"))
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalized.string(key, locale: locale)
    }

    private func updateTaskStatus(to newStatus: TaskStatus) async {
        guard isUpdatingStatus == false else { return }
        isUpdatingStatus = true
        statusError = nil
        defer { isUpdatingStatus = false }

        if newStatus == .completed {
            await NotificationManager.shared.cancelAllPending(for: task.id)
        }

        do {
            let updated = try await scheduleViewModel.patchTaskStatus(taskId: task.id, to: newStatus)
            task = updated
            await refreshAssigneeLine()
            await loadForWhomProfiles()
            if newStatus == .completed, updated.isRecurring == false {
                showCompletedReminderCleanupAlert = true
            }
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
                    statusError = TaskDetailCopy.cannotResolveRecurringGroupForDelete(locale: locale)
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
                format: TaskDetailCopy.deleteFailedFormat(locale: locale),
                error.localizedDescription
            )
        }
        #else
        _ = scope
        statusError = TaskDetailCopy.supabaseSDKUnavailable(locale: locale)
        #endif
    }
}

// MARK: - Localized copy

private enum TaskDetailCopy {
    static func externalSyncReadOnlyBanner(locale: Locale) -> String { AppLocalized.string("This event was synced from an external calendar and cannot be edited in the app.", locale: locale) }
    static func tapToCallOrOpenLink(locale: Locale) -> String { AppLocalized.string("Double tap to call or open the link", locale: locale) }
    static func priorityUrgent(locale: Locale) -> String { AppLocalized.string("🔴 Urgent", locale: locale) }
    static func priorityNormal(locale: Locale) -> String { AppLocalized.string("🟢 Normal", locale: locale) }
    static func repeatNever(locale: Locale) -> String { AppLocalized.string("Never", locale: locale) }
    static func repeatDaily(locale: Locale) -> String { AppLocalized.string("Daily", locale: locale) }
    static func repeatWeekly(locale: Locale) -> String { AppLocalized.string("Weekly", locale: locale) }
    static func repeatMonthly(locale: Locale) -> String { AppLocalized.string("Monthly", locale: locale) }
    static func repeatCustom(locale: Locale) -> String { AppLocalized.string("Custom", locale: locale) }
    static func none(locale: Locale) -> String { AppLocalized.string("None", locale: locale) }
    static func listSeparator(locale: Locale) -> String { AppLocalized.string(", ", locale: locale) }
    static func reminderOnTime(locale: Locale) -> String { AppLocalized.string("On time", locale: locale) }
    static func reminder5Min(locale: Locale) -> String { AppLocalized.string("5 minutes before", locale: locale) }
    static func reminder10Min(locale: Locale) -> String { AppLocalized.string("10 minutes before", locale: locale) }
    static func reminder15Min(locale: Locale) -> String { AppLocalized.string("15 minutes before", locale: locale) }
    static func reminder30Min(locale: Locale) -> String { AppLocalized.string("30 minutes before", locale: locale) }
    static func reminder1Hour(locale: Locale) -> String { AppLocalized.string("1 hour before", locale: locale) }
    static func reminderMinutesBeforeFormat(locale: Locale) -> String { AppLocalized.string("%lld minutes before", locale: locale) }
    static func statusPendingAcceptance(locale: Locale) -> String { AppLocalized.string("Pending acceptance", locale: locale) }
    static func statusAccepted(locale: Locale) -> String { AppLocalized.string("Accepted", locale: locale) }
    static func statusInProgress(locale: Locale) -> String { AppLocalized.string("In progress", locale: locale) }
    static func statusCompleted(locale: Locale) -> String { AppLocalized.string("Completed", locale: locale) }
    static func statusIssue(locale: Locale) -> String { AppLocalized.string("Issue reported", locale: locale) }
    static func statusFailed(locale: Locale) -> String { AppLocalized.string("Failed", locale: locale) }
    static func statusExpired(locale: Locale) -> String { AppLocalized.string("Expired", locale: locale) }
    static func statusCancelled(locale: Locale) -> String { AppLocalized.string("Cancelled", locale: locale) }
    static func cannotResolveRecurringGroupForDelete(locale: Locale) -> String { AppLocalized.string("Could not resolve the recurring series group; bulk delete is unavailable.", locale: locale) }
    static func deleteFailedFormat(locale: Locale) -> String { AppLocalized.string("Delete failed: %@", locale: locale) }
    static func supabaseSDKUnavailable(locale: Locale) -> String { AppLocalized.string("Supabase SDK is not available in this build.", locale: locale) }
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
    }
}
