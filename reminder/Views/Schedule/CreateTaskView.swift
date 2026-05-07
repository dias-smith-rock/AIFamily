import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

extension Notification.Name {
    static let scheduleTasksDidChange = Notification.Name("scheduleTasksDidChange")
}

private enum RecurringTaskScope {
    case singleOnly
    case thisAndFuture
}

private struct RecurringTaskUpdateRPCParams: Encodable {
    let targetTaskId: UUID
    let updateScope: String
    let newTitle: String
    let newDescription: String?
    let newCost: Decimal?
    let newTargetIds: [UUID]?

    enum CodingKeys: String, CodingKey {
        case targetTaskId = "target_task_id"
        case updateScope = "update_scope"
        case newTitle = "new_title"
        case newDescription = "new_description"
        case newCost = "new_cost"
        case newTargetIds = "new_target_ids"
    }
}

struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    @FocusState private var focusedField: Field?

    @State private var title = ""
    @State private var dueDate = Date()
    @State private var isAllDay = false
    @State private var repeatOption: TaskRepeatOption = .never
    @State private var reminderOption: TaskReminderOption = .atTimeOfEvent

    @State private var selectedAssigneeIds: Set<UUID> = []
    @State private var assignees: [AssigneeOption] = []
    @State private var note = ""
    @State private var financeDetailNote = ""
    @State private var costInput = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var pendingRecurringUpdateTask: FamilyTask?
    @State private var isShowingRecurringUpdateScopeDialog = false

    private let editingTask: FamilyTask?
    private let onSaveSuccess: ((Date) -> Void)?
    private let onUpdateSuccess: ((FamilyTask) -> Void)?

    init(
        editingTask: FamilyTask? = nil,
        onSaveSuccess: ((Date) -> Void)? = nil,
        onUpdateSuccess: ((FamilyTask) -> Void)? = nil
    ) {
        self.editingTask = editingTask
        self.onSaveSuccess = onSaveSuccess
        self.onUpdateSuccess = onUpdateSuccess

        if let task = editingTask {
            _title = State(initialValue: task.title)
            _dueDate = State(initialValue: task.dueDate ?? task.originalDueDate ?? Date())
            _isAllDay = State(initialValue: task.isAllDay)
            _repeatOption = State(initialValue: TaskRepeatOption(recurrenceRule: task.recurrenceRule))
            _reminderOption = State(initialValue: TaskReminderOption(offsets: task.reminderOffsets))
            if task.involvesWholeHousehold {
                _selectedAssigneeIds = State(initialValue: [])
            } else {
                _selectedAssigneeIds = State(initialValue: Set(task.involvedMemberIds ?? []))
            }
            _note = State(initialValue: task.description ?? "")
            _financeDetailNote = State(initialValue: "")
            _costInput = State(initialValue: Self.displayCost(fromMinorUnits: task.estimatedCost))
        } else {
            _title = State(initialValue: "")
            _dueDate = State(initialValue: Date())
            _isAllDay = State(initialValue: false)
            _repeatOption = State(initialValue: .never)
            _reminderOption = State(initialValue: .atTimeOfEvent)
            _selectedAssigneeIds = State(initialValue: [])
            _note = State(initialValue: "")
            _financeDetailNote = State(initialValue: "")
            _costInput = State(initialValue: "")
        }
    }

    private enum Field: Hashable {
        case title
        case cost
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("准备做什么？", text: $title, axis: .vertical)
                        .font(.title3.weight(.semibold))
                        .lineLimit(3...8)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                }

                Section {
                    Toggle("全天", isOn: $isAllDay)

                    DatePicker(
                        isAllDay ? "执行日期" : "执行时间",
                        selection: $dueDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )

                    Picker("重复", selection: $repeatOption) {
                        ForEach(TaskRepeatOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }

                    Picker("提醒", selection: $reminderOption) {
                        ForEach(TaskReminderOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } header: {
                    Text("时间设置")
                }

                Section {
                    assigneeSectionContent
                } header: {
                    Text("任务分配")
                }

                Section {
                    moreDetailNoteEditor
                } header: {
                    Text("更多细节")
                }

                Section {
                    financeAndNotesSectionContent
                } header: {
                    Text("财务与备注")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(AppTheme.FontToken.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(editingTask == nil ? "新建任务" : "编辑任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            await saveTask()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(title.isEmpty || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.1)
                }
            }
            .onAppear {
                if editingTask == nil {
                    focusedField = .title
                }
            }
        }
        .task {
            await loadAssignees()
        }
        .confirmationDialog(
            "这是循环任务",
            isPresented: $isShowingRecurringUpdateScopeDialog,
            titleVisibility: .visible
        ) {
            Button("仅修改此任务") {
                guard let existing = pendingRecurringUpdateTask else { return }
                pendingRecurringUpdateTask = nil
                Task {
                    await performUpdate(existing: existing, scope: .singleOnly)
                }
            }
            Button("修改此任务及以后", role: .destructive) {
                guard let existing = pendingRecurringUpdateTask else { return }
                pendingRecurringUpdateTask = nil
                Task {
                    await performUpdate(existing: existing, scope: .thisAndFuture)
                }
            }
            Button("取消", role: .cancel) {
                pendingRecurringUpdateTask = nil
            }
        } message: {
            Text("请选择修改范围。")
        }
    }

    private var currencySymbol: String {
        Locale.current.currencySymbol ?? "¥"
    }

    @ViewBuilder
    private var moreDetailNoteEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $note)
                .font(AppTheme.FontToken.body)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)

            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("添加备注...")
                    .font(AppTheme.FontToken.body)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var financeAndNotesSectionContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "banknote")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("预计开销")
                .font(.body)
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Text(currencySymbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                TextField("0", text: $costInput)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .focused($focusedField, equals: .cost)
                    .frame(minWidth: 96)
            }
        }
        .onChange(of: costInput) { _, newValue in
            let normalized = Self.normalizedDecimalInput(newValue)
            if normalized != newValue {
                costInput = normalized
            }
        }

        financeDetailNoteEditor
    }

    private var financeDetailNoteEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("详细说明")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $financeDetailNote)
                    .font(AppTheme.FontToken.body)
                    .frame(minHeight: 80)
                    .scrollContentBackground(.hidden)

                if financeDetailNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("可填写开支明细、支付方式等…")
                        .font(AppTheme.FontToken.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                        .padding(.leading, 4)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private var assigneeSectionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("指派给")
                Spacer()
                Text(assigneeSummary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    assigneeChipAll

                    ForEach(assignees) { person in
                        assigneeChip(for: person)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var assigneeChipAll: some View {
        let isAll = selectedAssigneeIds.isEmpty
        return Button {
            selectedAssigneeIds = []
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isAll ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill))
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isAll ? Color.accentColor : Color.secondary)
                    if isAll {
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel("指派给所有人")
        .accessibilityAddTraits(isAll ? .isSelected : [])
    }

    private func assigneeChip(for person: AssigneeOption) -> some View {
        let selected = selectedAssigneeIds.contains(person.id)
        return Button {
            toggleAssignee(person.id)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color(.secondarySystemFill))
                        .frame(width: 52, height: 52)
                    Text(person.initials)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 18, y: 18)
                    }
                }
                Text(person.name)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: 72)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(person.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var assigneeSummary: String {
        if selectedAssigneeIds.isEmpty {
            return "所有人"
        }
        let names = assignees
            .filter { selectedAssigneeIds.contains($0.id) }
            .map(\.name)
        return names.isEmpty ? "所有人" : names.joined(separator: "、")
    }

    private func toggleAssignee(_ id: UUID) {
        if selectedAssigneeIds.isEmpty {
            selectedAssigneeIds = [id]
            return
        }
        if selectedAssigneeIds.contains(id) {
            selectedAssigneeIds.remove(id)
        } else {
            selectedAssigneeIds.insert(id)
        }
    }

    private func loadAssignees() async {
        guard let householdId = appRouter.selectedHouseholdId else { return }
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

            assignees = members.map { member in
                AssigneeOption(id: member.id, name: member.nickname)
            }
        } catch {
            assignees = []
        }
        #endif
    }

    private func saveTask() async {
        guard normalizedTitle.isEmpty == false else { return }
        guard let householdId = appRouter.selectedHouseholdId else {
            errorMessage = "当前未选择家庭。"
            return
        }
        guard let creatorMembershipId = appRouter.selectedMembershipId else {
            errorMessage = "当前成员身份无效，请重新进入家庭后再试。"
            return
        }

        #if canImport(Supabase)
        if let existing = editingTask {
            if existing.groupId != nil {
                pendingRecurringUpdateTask = existing
                isShowingRecurringUpdateScopeDialog = true
            } else {
                await performUpdate(existing: existing, scope: .singleOnly)
            }
            return
        }

        _ = creatorMembershipId
        await performCreate(householdId: householdId, creatorMembershipId: creatorMembershipId)
        #else
        errorMessage = "当前构建环境未包含 Supabase SDK。"
        #endif
    }

    private func performUpdate(existing: FamilyTask, scope: RecurringTaskScope) async {
        #if canImport(Supabase)
        guard let householdId = appRouter.selectedHouseholdId else {
            errorMessage = "当前未选择家庭。"
            return
        }
        guard existing.householdId == householdId else {
            errorMessage = "当前家庭与任务不一致，无法保存。"
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        do {
            let updated: FamilyTask
            switch scope {
            case .singleOnly:
                if existing.groupId != nil {
                    let rpcParams = RecurringTaskUpdateRPCParams(
                        targetTaskId: existing.id,
                        updateScope: "only_this",
                        newTitle: normalizedTitle,
                        newDescription: mergedDescriptionForPayload,
                        newCost: estimatedCostMajorUnits,
                        newTargetIds: resolvedInvolvedMemberIds
                    )
                    _ = try await SupabaseManager.shared.client
                        .rpc("update_recurring_tasks", params: rpcParams)
                        .execute()
                    updated = FamilyTask(
                        id: existing.id,
                        householdId: existing.householdId,
                        creatorId: existing.creatorId,
                        parentTaskId: existing.parentTaskId,
                        groupId: nil,
                        originalDueDate: existing.originalDueDate,
                        involvedMemberIds: resolvedInvolvedMemberIds,
                        targetSubject: existing.targetSubject,
                        title: normalizedTitle,
                        description: mergedDescriptionForPayload,
                        originalPrompt: existing.originalPrompt,
                        attachmentUrls: existing.attachmentUrls,
                        externalContacts: existing.externalContacts,
                        locationData: existing.locationData,
                        externalSyncRefs: existing.externalSyncRefs,
                        alarmSetBy: existing.alarmSetBy,
                        status: existing.status,
                        priority: existing.priority,
                        dueDate: dueDate,
                        isAllDay: isAllDay,
                        recurrenceRule: repeatOption.recurrenceRule,
                        reminderOffsets: reminderOption.reminderOffsetsMinutes,
                        estimatedCost: estimatedCostMinorUnits,
                        createdAt: existing.createdAt,
                        updatedAt: Date()
                    )
                } else {
                    let payload = TaskUpdatePayload(
                        title: normalizedTitle,
                        description: mergedDescriptionForPayload,
                        involvedMemberIds: resolvedInvolvedMemberIds,
                        dueDate: dueDate,
                        isAllDay: isAllDay,
                        recurrenceRule: repeatOption.recurrenceRule,
                        reminderOffsets: reminderOption.reminderOffsetsMinutes,
                        estimatedCost: estimatedCostMinorUnits,
                        updatedAt: Date()
                    )
                    updated = try await SupabaseManager.shared.client
                        .from("tasks")
                        .update(payload)
                        .eq("id", value: existing.id.uuidString)
                        .select()
                        .single()
                        .execute()
                        .value
                }
            case .thisAndFuture:
                guard existing.groupId != nil else {
                    errorMessage = "循环任务标识缺失。"
                    return
                }
                let rpcParams = RecurringTaskUpdateRPCParams(
                    targetTaskId: existing.id,
                    updateScope: "future",
                    newTitle: normalizedTitle,
                    newDescription: mergedDescriptionForPayload,
                    newCost: estimatedCostMajorUnits,
                    newTargetIds: resolvedInvolvedMemberIds
                )
                _ = try await SupabaseManager.shared.client
                    .rpc("update_recurring_tasks", params: rpcParams)
                    .execute()
                updated = FamilyTask(
                    id: existing.id,
                    householdId: existing.householdId,
                    creatorId: existing.creatorId,
                    parentTaskId: existing.parentTaskId,
                    groupId: existing.groupId,
                    originalDueDate: existing.originalDueDate,
                    involvedMemberIds: resolvedInvolvedMemberIds,
                    targetSubject: existing.targetSubject,
                    title: normalizedTitle,
                    description: mergedDescriptionForPayload,
                    originalPrompt: existing.originalPrompt,
                    attachmentUrls: existing.attachmentUrls,
                    externalContacts: existing.externalContacts,
                    locationData: existing.locationData,
                    externalSyncRefs: existing.externalSyncRefs,
                    alarmSetBy: existing.alarmSetBy,
                    status: existing.status,
                    priority: existing.priority,
                    dueDate: dueDate,
                    isAllDay: isAllDay,
                    recurrenceRule: repeatOption.recurrenceRule,
                    reminderOffsets: reminderOption.reminderOffsetsMinutes,
                    estimatedCost: estimatedCostMinorUnits,
                    createdAt: existing.createdAt,
                    updatedAt: Date()
                )
            }

            onUpdateSuccess?(updated)
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            dismiss()
        } catch {
            #if DEBUG
            print("[CreateTaskView] performUpdate failed: \(error.localizedDescription)")
            #endif
            errorMessage = "任务更新失败：\(error.localizedDescription)"
        }
        #else
        errorMessage = "当前构建环境未包含 Supabase SDK。"
        #endif
    }

    private func performCreate(householdId: UUID, creatorMembershipId: UUID) async {
        #if canImport(Supabase)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let now = Date()
            let creatorIdLowercased = creatorMembershipId.uuidString.lowercased()
            let recurrence = repeatOption.recurrenceRule
            let groupId: UUID? = recurrence == nil ? nil : UUID()
            let dates: [Date]
            if let recurrence {
                dates = generateFutureDates(start: dueDate, recurrenceRule: recurrence)
            } else {
                dates = [dueDate]
            }
            let payloads = dates.map { date in
                TaskInsertPayload(
                    id: UUID(),
                    householdId: householdId,
                    creatorId: creatorIdLowercased,
                    groupId: groupId,
                    involvedMemberIds: resolvedInvolvedMemberIds,
                    title: normalizedTitle,
                    description: mergedDescriptionForPayload,
                    status: TaskStatus.new.rawValue,
                    priority: TaskPriority.normal.rawValue,
                    dueDate: date,
                    isAllDay: isAllDay,
                    recurrenceRule: recurrence,
                    reminderOffsets: reminderOption.reminderOffsetsMinutes,
                    estimatedCost: estimatedCostMinorUnits,
                    createdAt: now,
                    updatedAt: now
                )
            }
            _ = try await SupabaseManager.shared.client
                .from("tasks")
                .insert(payloads)
                .execute()
            onSaveSuccess?(dueDate)
            NotificationCenter.default.post(name: .scheduleTasksDidChange, object: nil)
            dismiss()
        } catch {
            errorMessage = "任务保存失败：\(error.localizedDescription)"
        }
        #else
        _ = householdId
        _ = creatorMembershipId
        errorMessage = "当前构建环境未包含 Supabase SDK。"
        #endif
    }

    private func generateFutureDates(start: Date, recurrenceRule: String) -> [Date] {
        let calendar = Calendar.current
        guard
            let sixMonthsLater = calendar.date(byAdding: .month, value: 6, to: start)
        else {
            return [start]
        }
        let normalized = recurrenceRule.uppercased()
        let component: Calendar.Component
        switch normalized {
        case _ where normalized.contains("DAILY"):
            component = .day
        case _ where normalized.contains("WEEKLY"):
            component = .weekOfYear
        case _ where normalized.contains("MONTHLY"):
            component = .month
        default:
            return [start]
        }

        var dates: [Date] = [start]
        var cursor = start
        while dates.count < 30 {
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor) else { break }
            if next > sixMonthsLater { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }

    private static func displayCost(fromMinorUnits minor: Int?) -> String {
        guard let minor else { return "" }
        if minor == 0 { return "" }
        let value = Double(minor) / 100.0
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}

// MARK: - Repeat / Reminder

private enum TaskRepeatOption: String, CaseIterable, Identifiable {
    case never
    case daily
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return "从不"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    var recurrenceRule: String? {
        switch self {
        case .never: return nil
        case .daily: return "FREQ=DAILY"
        case .weekly: return "FREQ=WEEKLY"
        case .monthly: return "FREQ=MONTHLY"
        }
    }

    init(recurrenceRule: String?) {
        guard let rule = recurrenceRule?.trimmingCharacters(in: .whitespacesAndNewlines), rule.isEmpty == false else {
            self = .never
            return
        }
        if rule.contains("DAILY") {
            self = .daily
        } else if rule.contains("WEEKLY") {
            self = .weekly
        } else if rule.contains("MONTHLY") {
            self = .monthly
        } else {
            self = .never
        }
    }
}

private enum TaskReminderOption: String, CaseIterable, Identifiable {
    case none
    case atTimeOfEvent
    case minutesBefore10
    case hourBefore1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .atTimeOfEvent: return "准时"
        case .minutesBefore10: return "提前 10 分钟"
        case .hourBefore1: return "提前 1 小时"
        }
    }

    var reminderOffsetsMinutes: [Int]? {
        switch self {
        case .none: return nil
        case .atTimeOfEvent: return [0]
        case .minutesBefore10: return [10]
        case .hourBefore1: return [60]
        }
    }

    init(offsets: [Int]?) {
        guard let offsets, offsets.isEmpty == false else {
            self = .none
            return
        }
        if offsets == [0] {
            self = .atTimeOfEvent
        } else if offsets.contains(10) {
            self = .minutesBefore10
        } else if offsets.contains(60) {
            self = .hourBefore1
        } else {
            self = .atTimeOfEvent
        }
    }
}

private struct AssigneeOption: Identifiable, Equatable {
    let id: UUID
    let name: String

    var initials: String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = t.first else { return "?" }
        return String(c).uppercased()
    }
}

private struct TaskInsertPayload: Encodable {
    let id: UUID
    let householdId: UUID
    let creatorId: String
    let groupId: UUID?
    let involvedMemberIds: [UUID]?
    let title: String
    let description: String?
    let status: String
    let priority: String
    let dueDate: Date
    let isAllDay: Bool
    let recurrenceRule: String?
    let reminderOffsets: [Int]?
    let estimatedCost: Int?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case creatorId = "creator_id"
        case groupId = "group_id"
        case involvedMemberIds = "involved_member_ids"
        case title
        case description
        case status
        case priority
        case dueDate = "due_date"
        case isAllDay = "is_all_day"
        case recurrenceRule = "recurrence_rule"
        case reminderOffsets = "reminder_offsets"
        case estimatedCost = "estimated_cost"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(creatorId, forKey: .creatorId)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        if let involvedMemberIds {
            try container.encode(involvedMemberIds, forKey: .involvedMemberIds)
        } else {
            try container.encodeNil(forKey: .involvedMemberIds)
        }
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct TaskUpdatePayload: Encodable {
    let title: String
    let description: String?
    let involvedMemberIds: [UUID]?
    let dueDate: Date
    let isAllDay: Bool
    let recurrenceRule: String?
    let reminderOffsets: [Int]?
    let estimatedCost: Int?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case involvedMemberIds = "involved_member_ids"
        case dueDate = "due_date"
        case isAllDay = "is_all_day"
        case recurrenceRule = "recurrence_rule"
        case reminderOffsets = "reminder_offsets"
        case estimatedCost = "estimated_cost"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        if let involvedMemberIds {
            try container.encode(involvedMemberIds, forKey: .involvedMemberIds)
        } else {
            try container.encodeNil(forKey: .involvedMemberIds)
        }
        try container.encode(dueDate, forKey: .dueDate)
        try container.encode(isAllDay, forKey: .isAllDay)
        try container.encodeIfPresent(recurrenceRule, forKey: .recurrenceRule)
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private extension CreateTaskView {
    /// 「所有人」写入 `nil`；否则写入所选 membership id 列表。
    var resolvedInvolvedMemberIds: [UUID]? {
        if selectedAssigneeIds.isEmpty {
            return nil
        }
        return Array(selectedAssigneeIds)
    }

    var normalizedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var normalizedFinanceDetailNote: String? {
        let value = financeDetailNote.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// 表上仅 `description` 一列时，将「更多细节」与「财务详细说明」合并写入。
    var mergedDescriptionForPayload: String? {
        let a = normalizedNote
        let b = normalizedFinanceDetailNote
        switch (a, b) {
        case (nil, nil):
            return nil
        case (let x?, nil):
            return x
        case (nil, let y?):
            return y
        case (let x?, let y?):
            return "\(x)\n\n\(y)"
        }
    }

    var estimatedCostMinorUnits: Int? {
        let t = costInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return nil }
        guard let value = Double(t) else { return nil }
        return Int((value * 100).rounded())
    }

    var estimatedCostMajorUnits: Decimal? {
        let t = costInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.isEmpty == false else { return nil }
        return Decimal(string: t)
    }

    static func normalizedDecimalInput(_ raw: String) -> String {
        var output = ""
        var sawDot = false
        for ch in raw {
            if ("0" ... "9").contains(ch) {
                output.append(ch)
            } else if ch == "." || ch == "," {
                if sawDot == false {
                    output.append(".")
                    sawDot = true
                }
            }
        }
        return output
    }
}

#Preview {
    CreateTaskView()
        .environmentObject(AppRouter())
}
