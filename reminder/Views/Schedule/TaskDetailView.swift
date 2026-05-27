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
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
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
                            Text("编辑")
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
            await loadForWhomProfiles()
        }
        .confirmationDialog(
            "删除任务",
            isPresented: $isShowingDeleteScopeDialog,
            titleVisibility: .visible
        ) {
            if task.seriesGrouping == nil {
                Button("仅删除此任务", role: .destructive) {
                    Task { await performDelete(scope: .singleOnly) }
                }
            } else {
                Button("仅删除此任务", role: .destructive) {
                    Task { await performDelete(scope: .singleOnly) }
                }
                Button("删除此任务及以后", role: .destructive) {
                    Task { await performDelete(scope: .thisAndFuture) }
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text(task.seriesGrouping == nil ? "此操作不可撤销。" : "请选择删除范围。")
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
            Text("此日程由外部同步，暂不支持在应用内修改")
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
            TaskDetailRowView(systemImage: "repeat", label: "重复") {
                Text(inferredRecurrenceRule.titleKey)
            }
            cardDivider
            TaskDetailRowView(systemImage: "bell", label: "提醒") {
                TaskReminderLabel.valueView(offsets: task.reminderOffsets)
            }
            cardDivider
            TaskDetailRowView(systemImage: "person", label: "谁去办 (Assignee)") {
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
                label: "预计开销",
                valueIsPlaceholder: costIsEmpty
            ) {
                costValueView
            }
            cardDivider
            TaskDetailRowView(
                systemImage: "tag",
                label: "当前状态",
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
            from: task.recurrenceRule,
            recurrenceInterval: task.recurrenceInterval
        )
    }

    private var timePlanningCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("时间规划")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                if task.isAllDay {
                    timePlanningLine(label: "时间") {
                        Text("全天")
                    }
                } else {
                    timePlanningLine(label: "开始时间") {
                        Text(timePlanningStartText)
                    }
                    if let endText = timePlanningEndText {
                        timePlanningLine(label: "结束时间") {
                            Text(endText)
                        }
                    }
                    timePlanningLine(label: "总花费时间") {
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
            (Text(label) + Text(verbatim: ":"))
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

    // MARK: - 为了谁（纯展示）

    private var forWhomSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "person.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("为了谁")
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
            Text("所有人")
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("为了谁：全体成员")
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
                Text("显示更多选项")
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
                Text("收起更多选项")
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
            expandedCard(title: "任务优先级") {
                priorityReadonlySegmentVisual
            }

            expandedCard(title: "紧急联系号码 / 会议链接") {
                emergencyReadonlyBlock
            }

            expandedCard(title: "地理位置") {
                locationReadonlyRow
            }

            expandedCard(title: "更多细节") {
                readonlyMultilineBlock(
                    text: descriptionMoreDetailsPart,
                    emptyPlaceholder: "暂无备注"
                )
            }

            expandedCard(title: "财务与备注") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("预计开销")
                            .font(.body)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        costValueView
                            .font(.body.weight(.medium))
                            .foregroundStyle(financeCostIsPlaceholder ? .tertiary : .primary)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("详细说明")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        readonlyMultilineBlock(
                            text: descriptionFinancePart,
                            emptyPlaceholder: "可填写开支明细、支付方式等…",
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
            Text("紧急")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isUrgent ? Color.accentColor : Color.secondary)
                .background(isUrgent ? Color.accentColor.opacity(0.18) : Color.clear)

            Text("一般")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .foregroundStyle(isUrgent ? Color.secondary : Color.accentColor)
                .background(isUrgent ? Color.clear : Color.accentColor.opacity(0.18))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("任务优先级")
        .accessibilityValue(task.priority.localizedName)
    }

    private var emergencyReadonlyBlock: some View {
        let trimmed = task.emergencyPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return HStack(alignment: .center, spacing: 10) {
            Group {
                if trimmed.isEmpty {
                    Text("无")
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
                    Text("尚未添加位置")
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
                .accessibilityHint("轻点两下以拨打或打开链接")
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

    private var costIsEmpty: Bool {
        guard let minor = task.estimatedCost else { return true }
        return minor == 0
    }

    @ViewBuilder
    private var costValueView: some View {
        if costIsEmpty {
            Text("无")
        } else if let minor = task.estimatedCost {
            Text(verbatim: formattedCostAmount(minorUnits: minor))
        } else {
            Text("无")
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
        switch currentUserRole {
        case .admin, .creator: return true
        case .member: return false
        }
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
                    statusFooterPrimaryButton("接受任务", tint: .orange) {
                        Task { await updateTaskStatus(to: .accepted) }
                    }

                case .accepted:
                    VStack(spacing: 12) {
                        statusFooterPrimaryButton("完成任务", tint: .green) {
                            Task { await updateTaskStatus(to: .completed) }
                        }

                        Button {
                            Task { await updateTaskStatus(to: .issue) }
                        } label: {
                            Text("遇到问题")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(isUpdatingStatus)
                    }

                case .inProgress:
                    statusFooterPrimaryButton("标记为完成", tint: .green) {
                        Task { await updateTaskStatus(to: .completed) }
                    }

                default:
                    Text("✅ 该任务已完结")
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
        .alert("任务已完成", isPresented: $showCompletedReminderCleanupAlert) {
            Button("是") {
                Task {
                    await NotificationManager.shared.cancelAllPending(for: task.id)
                }
            }
            Button("否", role: .cancel) {}
        } message: {
            Text("是否需要为您删除对应的闹钟提醒？")
        }
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
                    statusError = String(
                        localized: "无法解析重复任务分组，无法批量删除。",
                        locale: locale
                    )
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
                format: String(localized: "删除失败：%@", locale: locale),
                error.localizedDescription
            )
        }
        #else
        _ = scope
        statusError = String(localized: "当前构建环境未包含 Supabase SDK。", locale: locale)
        #endif
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
