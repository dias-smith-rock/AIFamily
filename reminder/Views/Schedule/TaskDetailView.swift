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

private struct RecurringTaskDeleteRPCParams: Encodable {
    let targetTaskId: UUID
    let deleteScope: String

    enum CodingKeys: String, CodingKey {
        case targetTaskId = "target_task_id"
        case deleteScope = "delete_scope"
    }
}

struct TaskDetailView: View {
    @EnvironmentObject private var appRouter: AppRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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
                titleHeader
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                coreInfoCard
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
            statusMachineFooter
        }
        .sheet(isPresented: $showingEditSheet) {
            EditTaskView(task: task) { updated in
                task = updated
                Task {
                    await scheduleViewModel.loadTasks()
                    await refreshAssigneeLine()
                    await loadForWhomProfiles()
                }
            }
            .environmentObject(appRouter)
            .presentationDragIndicator(.visible)
        }
        .task(id: task.id) {
            await refreshAssigneeLine()
            await loadForWhomProfiles()
        }
        .confirmationDialog(
            "删除任务",
            isPresented: $isShowingDeleteScopeDialog,
            titleVisibility: .visible
        ) {
            if task.groupId == nil {
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
            Text(task.groupId == nil ? "此操作不可撤销。" : "请选择删除范围。")
        }
        .onChange(of: appRouter.selectedHouseholdId) { _, _ in
            Task {
                await refreshAssigneeLine()
                await loadForWhomProfiles()
            }
        }
        .preference(key: ScheduleAssistantFABVisibility.PreferenceKey.self, value: true)
    }

    // MARK: - Layout

    private var bottomScrollPadding: CGFloat {
        120
    }

    // MARK: - 大标题

    private var titleHeader: some View {
        Text(task.title)
            .font(.largeTitle)
            .fontWeight(.bold)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - 核心信息卡片（始终）

    private var coreInfoCard: some View {
        VStack(spacing: 0) {
            coreRow(systemImage: "calendar", label: "时间", value: primaryScheduleText)
            cardDivider
            coreRow(systemImage: "repeat", label: "重复", value: repeatDisplayText)
            cardDivider
            coreRow(systemImage: "bell", label: "提醒", value: reminderDisplayText)
            cardDivider
            coreRow(systemImage: "person", label: "谁去办", value: assigneeLine)
            cardDivider
            coreRow(systemImage: "banknote", label: "预计开销", value: costDisplayText, valueIsPlaceholder: costIsEmpty)
            cardDivider
            coreRow(
                systemImage: "tag",
                label: "当前状态",
                value: statusFriendlyLabel,
                valueAccent: task.status == .new
            )
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
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
        .accessibilityLabel("为了谁：全家人")
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
                    Text(profileInitials(profile.name))
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

            Text(profile.name)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(profile.name)
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
                        Text(financeCostLineText)
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

    private var financeCostLineText: String {
        costDisplayText
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
        .accessibilityLabel("任务优先级：\(priorityReadonlyText)")
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
            Text(has ? (locationLine ?? "") : "尚未添加位置")
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
            return "🔴 紧急"
        case .normal, .low:
            return "🟢 一般"
        @unknown default:
            return "🟢 一般"
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
                .accessibilityHint("轻点以拨打或打开链接")
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

    private var primaryScheduleText: String {
        let start = scheduledAt
        if task.isAllDay {
            var s = Self.dayFormatter.string(from: start)
            if let end = task.endDatetime {
                s += " – \(Self.dayFormatter.string(from: end))"
            }
            return s
        }
        var base = Self.dateTimeFormatter.string(from: start)
        if let end = task.endDatetime, end > start {
            base += " – \(Self.timeFormatter.string(from: end))"
        }
        return base
    }

    private var scheduledAt: Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private static let chineseCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = chineseCalendar
        formatter.dateFormat = "M月d日 EEEE HH:mm"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = chineseCalendar
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = chineseCalendar
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private var repeatDisplayText: String {
        guard let rule = task.recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines),
              rule.isEmpty == false else {
            return "永不"
        }
        if rule.uppercased().contains("DAILY") { return "每天" }
        if rule.uppercased().contains("WEEKLY") { return "每周" }
        if rule.uppercased().contains("MONTHLY") { return "每月" }
        return "自定义"
    }

    private var reminderDisplayText: String {
        guard let offsets = task.reminderOffsets, offsets.isEmpty == false else {
            return "无"
        }
        return offsets.sorted().map(reminderLabel(forMinutes:)).joined(separator: "、")
    }

    private func reminderLabel(forMinutes m: Int) -> String {
        switch m {
        case 0: return "准时"
        case 10: return "提前 10 分钟"
        case 60: return "提前 1 小时"
        default: return "提前 \(m) 分钟"
        }
    }

    private var costIsEmpty: Bool {
        guard let minor = task.estimatedCost else { return true }
        return minor == 0
    }

    private var costDisplayText: String {
        guard let minor = task.estimatedCost else { return "无" }
        if minor == 0 { return "无" }
        let value = Double(minor) / 100.0
        let symbol = Locale.current.currencySymbol ?? "¥"
        if value == floor(value) {
            return String(format: "%@%.0f", symbol, value)
        }
        return String(format: "%@%.1f", symbol, value)
    }

    private var statusFriendlyLabel: String {
        switch task.status {
        case .new: return "待接受"
        case .accepted: return "已接受"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        case .issue: return "遇到问题"
        case .failed: return "执行失败"
        case .expired: return "已过期"
        case .cancelled: return "已取消"
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
        if task.involvesWholeHousehold {
            assigneeLine = "所有人"
            return
        }
        guard let ids = task.involvedMemberIds, ids.isEmpty == false else {
            assigneeLine = "所有人"
            return
        }
        let householdId = appRouter.selectedHouseholdId ?? task.householdId

        #if canImport(Supabase)
        do {
            let members: [HouseholdMembership] = try await SupabaseManager.shared.client
                .from("household_memberships")
                .select()
                .eq("household_id", value: householdId.uuidString)
                .eq("status", value: MembershipStatus.active.rawValue)
                .order("created_at", ascending: true)
                .execute()
                .value

            let names = ids.compactMap { id in members.first(where: { $0.id == id })?.nickname }
            if names.isEmpty {
                assigneeLine = assigneeDisplayNameFallback
            } else {
                assigneeLine = names.joined(separator: "、")
            }
        } catch {
            assigneeLine = assigneeDisplayNameFallback
        }
        #else
        assigneeLine = assigneeDisplayNameFallback
        #endif
    }

    @MainActor
    private func loadForWhomProfiles() async {
        let householdId = appRouter.selectedHouseholdId ?? task.householdId
        #if canImport(Supabase)
        do {
            let rows: [FamilyProfile] = try await SupabaseManager.shared.client
                .from("family_profiles")
                .select("id,household_id,name,user_id,avatar_url")
                .eq("household_id", value: householdId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            forWhomProfiles = rows
        } catch {
            forWhomProfiles = []
        }
        #else
        forWhomProfiles = []
        #endif
    }

    private var canEditTask: Bool {
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
                        Text("接受任务")
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
                            Text("完成任务")
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
                            Text("遇到问题")
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
                        Text("标记为完成")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .disabled(isUpdatingStatus)

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
    }

    private func updateTaskStatus(to newStatus: TaskStatus) async {
        guard isUpdatingStatus == false else { return }
        isUpdatingStatus = true
        statusError = nil
        defer { isUpdatingStatus = false }

        do {
            let updated = try await scheduleViewModel.patchTaskStatus(taskId: task.id, to: newStatus)
            task = updated
            await refreshAssigneeLine()
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
                if task.groupId != nil {
                    let params = RecurringTaskDeleteRPCParams(
                        targetTaskId: task.id,
                        deleteScope: "only_this"
                    )
                    _ = try await SupabaseManager.shared.client
                        .rpc("delete_recurring_tasks", params: params)
                        .execute()
                    await scheduleViewModel.loadTasks()
                } else {
                    await scheduleViewModel.deleteTask(taskId: task.id)
                }
            case .thisAndFuture:
                guard task.groupId != nil else {
                    statusError = "循环任务标识缺失，无法批量删除。"
                    return
                }
                let params = RecurringTaskDeleteRPCParams(
                    targetTaskId: task.id,
                    deleteScope: "future"
                )
                _ = try await SupabaseManager.shared.client
                    .rpc("delete_recurring_tasks", params: params)
                    .execute()
                await scheduleViewModel.loadTasks()
            }
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            dismiss()
        } catch {
            statusError = "删除失败：\(error.localizedDescription)"
        }
        #else
        _ = scope
        statusError = "当前构建环境未包含 Supabase SDK。"
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
