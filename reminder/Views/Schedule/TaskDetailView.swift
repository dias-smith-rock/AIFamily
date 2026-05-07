import SwiftUI

//
//  任务详情由 `ScheduleView` 以 `.sheet(item:)` 弹出；内部使用 `NavigationStack` 承载标题栏与「完成 / 编辑」Toolbar。
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
    @ObservedObject private var scheduleViewModel: ScheduleViewModel

    private let currentUserRole: MembershipRole
    private let assigneeDisplayNameFallback: String

    @State private var task: FamilyTask
    @State private var showingEditSheet = false
    @State private var isUpdatingStatus = false
    @State private var isDeletingTask = false
    @State private var statusError: String?
    @State private var assigneeLine: String
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
                headerBlock
                    .padding(.horizontal, 20)
                    .padding(.top, 4)

                attributeCard
                    .padding(.horizontal, 16)
                    .padding(.top, 20)

                if let statusError {
                    Text(statusError)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, bottomScrollPadding)
        }
        .background(Color(.systemGroupedBackground))
        // Sheet 内嵌 NavigationStack 时：标题 + Toolbar（完成 / 编辑）
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.automatic, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("完成") {
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
                }
            }
            .environmentObject(appRouter)
            .presentationDragIndicator(.visible)
        }
        .task(id: task.id) {
            await refreshAssigneeLine()
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
            Task { await refreshAssigneeLine() }
        }
        .preference(key: ScheduleAssistantFABVisibility.PreferenceKey.self, value: true)
    }

    // MARK: - Layout

    private var bottomScrollPadding: CGFloat {
        28
    }

    // MARK: - 标题区

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)

            if let description = task.description?.trimmingCharacters(in: .whitespacesAndNewlines),
               description.isEmpty == false {
                Text(description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 属性卡片

    private var attributeCard: some View {
        VStack(spacing: 0) {
            attributeRow(
                systemImage: "calendar",
                label: "时间",
                value: primaryScheduleText
            )
            cardDivider

            attributeRow(
                systemImage: "repeat",
                label: "重复",
                value: repeatDisplayText
            )
            cardDivider

            attributeRow(
                systemImage: "bell",
                label: "提醒",
                value: reminderDisplayText
            )
            cardDivider

            attributeRow(
                systemImage: "person.2",
                label: "指派给",
                value: assigneeLine
            )
            cardDivider

            attributeRow(
                systemImage: "banknote",
                label: "预计开销",
                value: costDisplayText
            )
            cardDivider

            attributeRow(
                systemImage: "tag",
                label: "当前状态",
                value: statusFriendlyLabel
            )

            if let location = locationLine {
                cardDivider
                attributeRow(
                    systemImage: "location",
                    label: "地点",
                    value: location
                )
            }
        }
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var cardDivider: some View {
        Divider()
            .padding(.leading, 52)
    }

    private func attributeRow(systemImage: String, label: String, value: String) -> some View {
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
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - 属性格式化

    private var primaryScheduleText: String {
        if task.isAllDay {
            return Self.dayFormatter.string(from: scheduledAt)
        }
        return Self.dateTimeFormatter.string(from: scheduledAt)
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

    private var costDisplayText: String {
        guard let minor = task.estimatedCost else { return "—" }
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

    // MARK: - 指派明细

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
        guard let householdId = appRouter.selectedHouseholdId else {
            assigneeLine = assigneeDisplayNameFallback
            return
        }

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

    private var canEditTask: Bool {
        switch currentUserRole {
        case .admin, .creator: return true
        case .member: return false
        }
    }

    // MARK: - 底部状态机（挂于 ScrollView.safeAreaInset）

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
