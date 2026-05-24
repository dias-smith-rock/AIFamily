import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

// MARK: - 表单卡片样式（供隔离子视图复用）

private struct CreateTaskFormCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 3)
    }
}

private extension View {
    func createTaskFormCardStyled() -> some View {
        modifier(CreateTaskFormCardStyle())
    }
}

private enum CreateTaskFocusField: Hashable {
    case title
    case cost
    case emergency
    case locationSearch
}

/// 「时间设置 + 重复设置」与标题输入解耦：仅在令牌字段变化时重绘，减轻 TextEditor 输入时的卡顿。
private struct CreateTaskTimeRecurrenceBlock: View, Equatable {
    let dueDateToken: Date
    let isAllDayToken: Bool
    let durationPickerToken: Date
    let selectedRecurrenceToken: TaskRecurrenceRule
    let recurrenceIntervalToken: Int
    let recurrenceEndDateToken: Date
    let showEndDateToken: Bool

    @Binding var dueDate: Date
    @Binding var isAllDay: Bool
    @Binding var durationPickerDate: Date
    @Binding var selectedRecurrence: TaskRecurrenceRule
    @Binding var recurrenceInterval: Int
    @Binding var recurrenceEndDate: Date
    @Binding var showEndDate: Bool

    let onRecurrenceChanged: (TaskRecurrenceRule) -> Void

    static func == (lhs: CreateTaskTimeRecurrenceBlock, rhs: CreateTaskTimeRecurrenceBlock) -> Bool {
        lhs.dueDateToken == rhs.dueDateToken
            && lhs.isAllDayToken == rhs.isAllDayToken
            && lhs.durationPickerToken == rhs.durationPickerToken
            && lhs.selectedRecurrenceToken == rhs.selectedRecurrenceToken
            && lhs.recurrenceIntervalToken == rhs.recurrenceIntervalToken
            && lhs.recurrenceEndDateToken == rhs.recurrenceEndDateToken
            && lhs.showEndDateToken == rhs.showEndDateToken
    }

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                Text("时间设置")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                Toggle("全天", isOn: $isAllDay)

                if isAllDay {
                    DatePicker(
                        "执行日期",
                        selection: $dueDate,
                        displayedComponents: [.date]
                    )
                    .datePickerStyle(.compact)

                    taskDurationRow
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        Text("执行时间")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .leading)

                        DatePicker(
                            "",
                            selection: $dueDate,
                            displayedComponents: [.date]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)

                        DatePicker(
                            "",
                            selection: $dueDate,
                            displayedComponents: [.hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                    }

                    taskDurationRow
                }
            }
            .createTaskFormCardStyled()

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    Text("重复设置")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Picker("重复", selection: $selectedRecurrence) {
                        ForEach(TaskRecurrenceRule.allCases) { rule in
                            Text(rule.displayName).tag(rule)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel("重复")
                }

                if selectedRecurrence == .custom {
                    Stepper("每隔 \(recurrenceInterval) 天", value: $recurrenceInterval, in: 2 ... 365)
                }

                if selectedRecurrence != .none {
                    Toggle("指定重复结束日期", isOn: $showEndDate)
                    if showEndDate {
                        DatePicker("结束重复", selection: $recurrenceEndDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }
            }
            .createTaskFormCardStyled()
            .onChange(of: selectedRecurrence) { _, newValue in
                onRecurrenceChanged(newValue)
            }
        }
    }

    private var taskDurationRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Label("任务时长", systemImage: "hourglass")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker(
                "",
                selection: $durationPickerDate,
                displayedComponents: [.hourAndMinute]
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .accessibilityLabel("任务时长")
        }
    }
}

extension Notification.Name {
    static let scheduleTasksDidChange = Notification.Name("scheduleTasksDidChange")
    /// `object`：`UUID`（`households.id`）。家庭页保存成员/档案后发出，日程列表应刷新 roster 缓存。
    static let scheduleHouseholdRosterDidChange = Notification.Name("scheduleHouseholdRosterDidChange")
    static let householdDidDisband = Notification.Name("householdDidDisband")
}

private enum RecurringTaskScope {
    case singleOnly
    case thisAndFuture
}

/// 单次编辑后脱离重复链：清空 `parent_task_id` / `group_id`。
private struct TaskClearSeriesLinksPatch: Encodable {
    enum CodingKeys: String, CodingKey {
        case parentTaskId = "parent_task_id"
        case groupId = "group_id"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeNil(forKey: .parentTaskId)
        try c.encodeNil(forKey: .groupId)
    }
}

struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    @FocusState private var focusedField: CreateTaskFocusField?

    @State private var title = ""
    @State private var dueDate = Date()
    @State private var durationPickerDate = CreateTaskView.makeDurationPickerDate(minutes: FamilyTask.defaultDurationMinutes)
    @State private var isAllDay = false
    @State private var selectedRecurrence: TaskRecurrenceRule = .none
    /// 「每隔几天」步进值（仅 `custom` 使用，范围 2…365）。
    @State private var recurrenceInterval: Int = 2
    @State private var recurrenceEndDate: Date = Date()
    @State private var showEndDate: Bool = false
    @State private var reminderOption: TaskReminderOption = .minutesBefore15

    @State private var selectedAssigneeIds: Set<UUID> = []
    /// `family_profiles.id`：「为了谁」；空表示未限定具体档案（全家）。
    @State private var selectedTargetProfileIds: Set<UUID> = []
    @State private var assignees: [AssigneeOption] = []
    @State private var forWhomProfileOptions: [AssigneeOption] = []
    @State private var note = ""
    @State private var financeDetailNote = ""
    @State private var costInput = ""
    @State private var selectedBackgroundHex: String?
    @State private var emergencyPhone = ""
    @State private var isShowingMoreOptions = false
    @State private var formPriority: TaskPriority = .normal
    @State private var locationName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var pendingRecurringUpdateTask: FamilyTask?
    @State private var isShowingRecurringUpdateScopeDialog = false

    private let editingTask: FamilyTask?
    private let initialTitle: String?
    private let onSaveSuccess: ((Date) -> Void)?
    private let onUpdateSuccess: ((FamilyTask) -> Void)?
    /// 保存成功后同步本地通知（由外层注入 `ScheduleViewModel.syncAlarms`）。须为同步闭包，避免再经 `async` 传递 `FamilyTask`。
    private let onAlarmSync: ((FamilyTask) -> Void)?

    init(
        editingTask: FamilyTask? = nil,
        initialTitle: String? = nil,
        defaultDueDate: Date? = nil,
        defaultAllDayForNewTask: Bool = true,
        onSaveSuccess: ((Date) -> Void)? = nil,
        onUpdateSuccess: ((FamilyTask) -> Void)? = nil,
        onAlarmSync: ((FamilyTask) -> Void)? = nil
    ) {
        self.editingTask = editingTask
        self.initialTitle = initialTitle
        self.onSaveSuccess = onSaveSuccess
        self.onUpdateSuccess = onUpdateSuccess
        self.onAlarmSync = onAlarmSync

        if let task = editingTask {
            _title = State(initialValue: task.title)
            let initialDue = task.dueDate ?? task.originalDueDate ?? Date()
            _dueDate = State(initialValue: initialDue)
            _durationPickerDate = State(
                initialValue: Self.makeDurationPickerDate(minutes: max(1, task.durationMinutes))
            )
            _isAllDay = State(initialValue: task.isAllDay)
            let inferred = TaskRecurrenceRule.inferred(from: task.recurrenceRule, recurrenceInterval: task.recurrenceInterval)
            _selectedRecurrence = State(initialValue: inferred)
            let customFromTask = max(2, min(365, task.recurrenceInterval ?? 2))
            _recurrenceInterval = State(initialValue: inferred == .custom ? customFromTask : 2)
            let defaultEndIfNeeded = Calendar.current.date(byAdding: .month, value: 6, to: initialDue) ?? initialDue
            _recurrenceEndDate = State(initialValue: task.recurrenceEndDate ?? defaultEndIfNeeded)
            _showEndDate = State(initialValue: task.recurrenceEndDate != nil)
            _reminderOption = State(initialValue: TaskReminderOption(offsets: task.reminderOffsets))
            if task.involvesWholeHousehold {
                _selectedAssigneeIds = State(initialValue: [])
            } else {
                _selectedAssigneeIds = State(initialValue: Set(task.involvedMemberIds ?? []))
            }
            if let profileIds = task.targetProfileIds, profileIds.isEmpty == false {
                _selectedTargetProfileIds = State(initialValue: Set(profileIds))
            } else {
                _selectedTargetProfileIds = State(initialValue: [])
            }
            _note = State(initialValue: task.description ?? "")
            _financeDetailNote = State(initialValue: "")
            _costInput = State(initialValue: Self.displayCost(fromMinorUnits: task.estimatedCost))
            _selectedBackgroundHex = State(initialValue: Self.normalizedStoredHex(task.backgroundColor))
            _emergencyPhone = State(initialValue: task.emergencyPhone ?? "")
            _formPriority = State(initialValue: Self.priorityForForm(task.priority))
            _locationName = State(initialValue: task.locationData?.name ?? "")
        } else {
            _title = State(initialValue: initialTitle ?? "")
            let calendar = Calendar.current
            let resolvedDue: Date = {
                if let d = defaultDueDate {
                    return calendar.startOfDay(for: d)
                }
                return calendar.startOfDay(for: Date())
            }()
            _dueDate = State(initialValue: resolvedDue)
            _durationPickerDate = State(
                initialValue: Self.makeDurationPickerDate(minutes: FamilyTask.defaultDurationMinutes)
            )
            _isAllDay = State(initialValue: defaultAllDayForNewTask)
            _selectedRecurrence = State(initialValue: .none)
            _recurrenceInterval = State(initialValue: 2)
            _recurrenceEndDate = State(initialValue: Calendar.current.date(byAdding: .month, value: 6, to: resolvedDue) ?? resolvedDue)
            _showEndDate = State(initialValue: false)
            _reminderOption = State(initialValue: .minutesBefore15)
            _selectedAssigneeIds = State(initialValue: [])
            _selectedTargetProfileIds = State(initialValue: [])
            _note = State(initialValue: "")
            _financeDetailNote = State(initialValue: "")
            _costInput = State(initialValue: "")
            _selectedBackgroundHex = State(initialValue: nil)
            _emergencyPhone = State(initialValue: "")
            _formPriority = State(initialValue: .normal)
            _locationName = State(initialValue: "")
        }
    }

    private var activeRecurrenceRuleString: String? {
        selectedRecurrence.recurrenceRuleString(customDayInterval: recurrenceInterval)
    }

    private func applyDefaultRecurrenceEndDate(for rule: TaskRecurrenceRule) {
        let cal = Calendar.current
        let anchor = dueDate
        if rule == .none {
            showEndDate = false
            return
        }
        showEndDate = true
        if rule == .yearly {
            recurrenceEndDate = cal.date(byAdding: .year, value: 6, to: anchor) ?? anchor
        } else {
            recurrenceEndDate = cal.date(byAdding: .month, value: 6, to: anchor) ?? anchor
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        titleEditorCard

                        EquatableView(
                            content:                             CreateTaskTimeRecurrenceBlock(
                                dueDateToken: dueDate,
                                isAllDayToken: isAllDay,
                                durationPickerToken: durationPickerDate,
                                selectedRecurrenceToken: selectedRecurrence,
                                recurrenceIntervalToken: recurrenceInterval,
                                recurrenceEndDateToken: recurrenceEndDate,
                                showEndDateToken: showEndDate,
                                dueDate: $dueDate,
                                isAllDay: $isAllDay,
                                durationPickerDate: $durationPickerDate,
                                selectedRecurrence: $selectedRecurrence,
                                recurrenceInterval: $recurrenceInterval,
                                recurrenceEndDate: $recurrenceEndDate,
                                showEndDate: $showEndDate,
                                onRecurrenceChanged: { rule in
                                    applyDefaultRecurrenceEndDate(for: rule)
                                }
                            )
                        )

                        forWhomCard

                        if isShowingMoreOptions {
                            repeatReminderPriorityCard
                            emergencyContactCard
                            assigneeWhoDoesCard
                            locationCard
                            moreDetailsCard
                            financeCard
                        }

                        expandCollapseButton

                        if let errorMessage {
                            Text(errorMessage)
                                .font(AppTheme.FontToken.caption)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                if isSaving {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.1)
                }
            }
            .navigationTitle(editingTask == nil ? "新建任务 ✨" : "编辑任务")
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
                    .disabled(isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                if editingTask == nil {
                    focusedField = .title
                } else {
                    isShowingMoreOptions = true
                }
            }
            .task(id: editingTask?.parentTaskId) {
                await loadParentRecurrenceTemplateIfNeeded()
            }
        }
        .task(id: appRouter.selectedHouseholdId ?? editingTask?.householdId) {
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

    private func sheetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().createTaskFormCardStyled()
    }

    /// 标题独立成卡：输入时父视图仍会刷新，但下方「时间/重复」由 `EquatableView` 隔离，避免重复渲染重量级控件。
    private var titleEditorCard: some View {
        Group {
            ZStack(alignment: .bottomTrailing) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $title)
                        .font(.title3.weight(.semibold))
                        .frame(minHeight: isShowingMoreOptions ? 120 : 96)
                        .scrollContentBackground(.hidden)
                        .focused($focusedField, equals: .title)

                    if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(titlePlaceholderText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }

                if isShowingMoreOptions {
                    Button {
                        // 语音输入：占位，后续接入识别管线
                    } label: {
                        Image(systemName: "mic.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("语音输入")
                    .accessibilityHint("功能即将推出")
                }
            }
        }
        .createTaskFormCardStyled()
    }

    private var titlePlaceholderText: String {
        if isShowingMoreOptions {
            return "准备做什么？可以说：明天下午花 500 港币带老大去洗牙……"
        }
        return "准备做什么？"
    }

    private var forWhomCard: some View {
        sheetCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("为了谁 (FOR)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                forWhomChipsRow
            }
        }
    }

    private var repeatReminderPriorityCard: some View {
        sheetCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("提醒")
                        .font(.body)
                    Spacer()
                    Picker("", selection: $reminderOption) {
                        ForEach(TaskReminderOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                .padding(.vertical, 4)

                Divider().padding(.vertical, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("任务优先级")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $formPriority) {
                        Text("紧急").tag(TaskPriority.urgent)
                        Text("一般").tag(TaskPriority.normal)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.top, 4)
            }
        }
    }

    private var emergencyContactCard: some View {
        sheetCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("紧急联系号码 / 会议链接")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 10) {
                    TextField("输入号码或链接", text: $emergencyPhone)
                        .font(.body)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                        .focused($focusedField, equals: .emergency)

                    Button {
                        // 通讯录：占位
                    } label: {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("从通讯录选择")
                    .accessibilityHint("功能即将推出")
                }
            }
        }
    }

    private var assigneeWhoDoesCard: some View {
        sheetCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("谁去办 (Assignee)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    assigneeChipsRow(members: assigneesWithRegisteredAccount)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var locationCard: some View {
        sheetCard {
            HStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("搜索或添加位置", text: $locationName)
                    .font(.body)
                    .focused($focusedField, equals: .locationSearch)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var moreDetailsCard: some View {
        sheetCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("更多细节")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                moreDetailNoteEditor
            }
        }
    }

    private var financeCard: some View {
        sheetCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("财务与备注")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                financeAndNotesSectionContent
            }
        }
    }

    private var expandCollapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                isShowingMoreOptions.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Text(isShowingMoreOptions ? "收起更多选项" : "显示更多选项")
                    .font(.subheadline.weight(.semibold))
                Image(systemName: isShowingMoreOptions ? "chevron.up" : "chevron.down")
                    .font(.footnote.weight(.bold))
            }
            .foregroundStyle(.tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    /// 已绑定 `auth.users` 的成员（有账号），用于「谁去办」可选列表。
    private var assigneesWithRegisteredAccount: [AssigneeOption] {
        assignees.filter(\.hasRegisteredAccount)
    }

    @ViewBuilder
    private func assigneeChipsRow(members: [AssigneeOption]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                assigneeChipAll
                ForEach(members) { person in
                    assigneeChip(for: person)
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// 「为了谁」：`family_profiles` 行，与 `involved_member_ids`（身份）维度不同。
    private var forWhomChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                forWhomChipAll
                ForEach(forWhomProfileOptions) { person in
                    forWhomProfileChip(for: person)
                }
            }
            .padding(.vertical, 4)
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
                TextField("0", text: costInputBinding)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .focused($focusedField, equals: .cost)
                    .frame(minWidth: 96)
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

    private var assigneeChipAll: some View {
        everyoneChip(isSelected: selectedAssigneeIds.isEmpty, accessibilityLabel: "指派给所有人") {
            selectedAssigneeIds = []
        }
    }

    private var forWhomChipAll: some View {
        everyoneChip(isSelected: selectedTargetProfileIds.isEmpty, accessibilityLabel: "为了谁：全家人") {
            selectedTargetProfileIds = []
        }
    }

    private func everyoneChip(isSelected: Bool, accessibilityLabel: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill))
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    if isSelected {
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func assigneeChip(for person: AssigneeOption) -> some View {
        personChip(person: person, selected: selectedAssigneeIds.contains(person.id)) {
            toggleAssignee(person.id)
        }
    }

    private func forWhomProfileChip(for person: AssigneeOption) -> some View {
        personChip(person: person, selected: selectedTargetProfileIds.contains(person.id)) {
            toggleTargetProfile(person.id)
        }
    }

    private func personChip(person: AssigneeOption, selected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
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

    private var costInputBinding: Binding<String> {
        Binding(
            get: { costInput },
            set: { costInput = Self.normalizedDecimalInput($0) }
        )
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func toggleTargetProfile(_ id: UUID) {
        if selectedTargetProfileIds.isEmpty {
            selectedTargetProfileIds = [id]
            return
        }
        if selectedTargetProfileIds.contains(id) {
            selectedTargetProfileIds.remove(id)
        } else {
            selectedTargetProfileIds.insert(id)
        }
    }

    private func loadAssignees() async {
        let routerHouseholdId = appRouter.selectedHouseholdId
        let taskHouseholdId = editingTask?.householdId
        let householdId = routerHouseholdId ?? taskHouseholdId
        forWhomDebugLog(
            "load.start editingTaskId=\(editingTask?.id.uuidString ?? "nil") routerHousehold=\(routerHouseholdId?.uuidString ?? "nil") taskHousehold=\(taskHouseholdId?.uuidString ?? "nil") resolved=\(householdId?.uuidString ?? "nil")"
        )
        guard let householdId else {
            assignees = []
            forWhomProfileOptions = []
            forWhomDebugLog("load.aborted reason=no_resolved_household_id")
            return
        }
        #if canImport(Supabase)
        var members: [HouseholdMembership] = []
        var profiles: [FamilyProfile] = []

        do {
            members = try await SupabaseManager.shared.client
                .from("household_memberships")
                .select()
                .eq("household_id", value: householdId.uuidString)
                .eq("status", value: MembershipStatus.active.rawValue)
                .order("created_at", ascending: true)
                .execute()
                .value
            forWhomDebugLog(
                "household_memberships OK count=\(members.count) ids=\(members.map(\.id.uuidString).joined(separator: ","))"
            )
        } catch {
            forWhomDebugLog(
                "household_memberships FAILED household=\(householdId.uuidString) error=\(error.localizedDescription) detail=\(String(describing: error))"
            )
        }

        do {
            profiles = try await SupabaseManager.shared.client
                .from("family_profiles")
                .select(SupabaseProfileSelect.profilesWithMemberships)
                .eq("household_id", value: householdId.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            let summary = profiles.map { "\($0.displayName)(\($0.id.uuidString.prefix(8)))" }.joined(separator: "; ")
            forWhomDebugLog("family_profiles OK count=\(profiles.count) rows=[\(summary)]")
        } catch {
            forWhomDebugLog(
                "family_profiles FAILED household=\(householdId.uuidString) error=\(error.localizedDescription) detail=\(String(describing: error))"
            )
        }

        let mergedProfiles = FamilyProfile.mergingMembershipRows(profiles, memberships: members)

        assignees = members.map { member in
            AssigneeOption(
                id: member.id,
                name: MemberDisplayName.displayName(for: member, profiles: mergedProfiles),
                hasRegisteredAccount: member.userId != nil
            )
        }
        forWhomProfileOptions = mergedProfiles.map { profile in
            AssigneeOption(
                id: profile.id,
                name: profile.displayName,
                hasRegisteredAccount: profile.userId != nil
            )
        }
        forWhomDebugLog(
            "load.done assignees.count=\(assignees.count) forWhomProfileOptions.count=\(forWhomProfileOptions.count)"
        )
        #else
        assignees = []
        forWhomProfileOptions = []
        forWhomDebugLog("load.skip reason=no_supabase_sdk")
        #endif
    }

    private func forWhomDebugLog(_ message: String) {
        #if DEBUG
        print("🔎 [CreateTaskView.ForWhom] \(message)")
        #endif
    }

    private func saveTask() async {
        guard normalizedTitle.isEmpty == false else {
            errorMessage = "请先填写任务标题"
            return
        }
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
            if existing.needsRecurringScopeDialog {
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
            let client = SupabaseManager.shared.client
            let updated: FamilyTask

            switch scope {
            case .singleOnly:
                let payload = TaskUpdatePayload(
                    title: normalizedTitle,
                    description: mergedDescriptionForPayload,
                    involvedMemberIds: resolvedInvolvedMemberIds,
                    targetProfileIds: resolvedTargetProfileIds,
                    dueDate: dueDate,
                    endDatetime: resolvedEndDatetime(for: dueDate),
                    durationMinutes: resolvedDurationMinutes(for: dueDate),
                    isAllDay: isAllDay,
                    recurrenceRule: activeRecurrenceRuleString,
                    recurrenceEndDate: resolvedRecurrenceEndDateForPayload(),
                    recurrenceInterval: resolvedRecurrenceIntervalForPayload(),
                    reminderOffsets: reminderOption.reminderOffsetsMinutes,
                    estimatedCost: estimatedCostMinorUnits,
                    backgroundColor: resolvedBackgroundColorHex(),
                    emergencyPhone: resolvedEmergencyPhoneForPayload(),
                    priority: formPriority.rawValue,
                    locationData: resolvedLocationData(),
                    updatedAt: Date()
                )
                var refreshed: FamilyTask = try await client
                    .from("tasks")
                    .update(payload)
                    .eq("id", value: existing.id.uuidString.lowercased())
                    .select()
                    .single()
                    .execute()
                    .value
                if existing.seriesGrouping != nil, shouldDetachSeriesOnSingleSave(existing) {
                    _ = try await client
                        .from("tasks")
                        .update(TaskClearSeriesLinksPatch())
                        .eq("id", value: existing.id.uuidString.lowercased())
                        .execute()
                    refreshed.parentTaskId = nil
                    refreshed.groupId = nil
                }
                updated = refreshed

            case .thisAndFuture:
                guard let grouping = existing.seriesGrouping else {
                    errorMessage = "无法解析重复任务分组。"
                    return
                }
                let cutoff = existing.dueDate ?? .distantPast
                let rows = try await TaskSeriesSupabaseSupport.fetchSeriesTasks(
                    householdId: householdId,
                    grouping: grouping,
                    dueOnOrAfter: cutoff
                )
                guard rows.isEmpty == false else {
                    errorMessage = "没有找到需要更新的任务。"
                    return
                }

                let calendar = Calendar.current
                let durationSeconds = TimeInterval(Self.durationMinutes(from: durationPickerDate) * 60)

                func isMotherMetaOnly(row: FamilyTask) -> Bool {
                    guard case .byParentRoot(let root) = grouping else { return false }
                    guard row.id == root else { return false }
                    return (row.dueDate ?? .distantPast) < cutoff && existing.id != row.id
                }

                var refreshedCurrent: FamilyTask?

                for row in rows {
                    let metaOnly = isMotherMetaOnly(row: row)
                    let newDue: Date
                    let newEnd: Date?
                    if row.id == existing.id {
                        newDue = dueDate
                        newEnd = resolvedEndDatetime(for: dueDate)
                    } else if metaOnly {
                        newDue = row.dueDate ?? dueDate
                        newEnd = row.endDatetime
                    } else {
                        newDue = RecurrenceEngine.mergeEditorTime(
                            editorDue: dueDate,
                            ontoOccurrence: row.dueDate,
                            allDay: isAllDay,
                            calendar: calendar
                        )
                        if isAllDay {
                            newEnd = nil
                        } else {
                            newEnd = newDue.addingTimeInterval(durationSeconds)
                        }
                    }

                    let recurrenceRulePayload: String?
                    let recurrenceEndPayload: Date?
                    let recurrenceIntervalPayload: Int?
                    switch grouping {
                    case .byParentRoot(let root):
                        recurrenceRulePayload = row.id == root
                            ? (activeRecurrenceRuleString ?? row.recurrenceRule)
                            : row.recurrenceRule
                        recurrenceEndPayload = row.id == root
                            ? resolvedRecurrenceEndDateForPayload()
                            : row.recurrenceEndDate
                        recurrenceIntervalPayload = row.id == root
                            ? resolvedRecurrenceIntervalForPayload()
                            : row.recurrenceInterval
                    case .byLegacyGroup:
                        recurrenceRulePayload = activeRecurrenceRuleString ?? row.recurrenceRule
                        recurrenceEndPayload = resolvedRecurrenceEndDateForPayload()
                        recurrenceIntervalPayload = resolvedRecurrenceIntervalForPayload()
                    }

                    let payload = TaskUpdatePayload(
                        title: normalizedTitle,
                        description: mergedDescriptionForPayload,
                        involvedMemberIds: resolvedInvolvedMemberIds,
                        targetProfileIds: resolvedTargetProfileIds,
                        dueDate: newDue,
                        endDatetime: newEnd,
                        durationMinutes: metaOnly
                            ? row.durationMinutes
                            : Self.durationMinutes(from: durationPickerDate),
                        isAllDay: isAllDay,
                        recurrenceRule: recurrenceRulePayload,
                        recurrenceEndDate: recurrenceEndPayload,
                        recurrenceInterval: recurrenceIntervalPayload,
                        reminderOffsets: reminderOption.reminderOffsetsMinutes,
                        estimatedCost: estimatedCostMinorUnits,
                        backgroundColor: resolvedBackgroundColorHex(),
                        emergencyPhone: resolvedEmergencyPhoneForPayload(),
                        priority: formPriority.rawValue,
                        locationData: resolvedLocationData(),
                        updatedAt: Date()
                    )
                    let rowUpdated: FamilyTask = try await client
                        .from("tasks")
                        .update(payload)
                        .eq("id", value: row.id.uuidString.lowercased())
                        .select()
                        .single()
                        .execute()
                        .value
                    if rowUpdated.id == existing.id {
                        refreshedCurrent = rowUpdated
                    }
                }

                guard let resolved = refreshedCurrent else {
                    errorMessage = "批量更新后未能定位当前任务。"
                    return
                }
                updated = resolved
            }

            onAlarmSync?(updated)
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

    private func shouldDetachSeriesOnSingleSave(_ task: FamilyTask) -> Bool {
        if task.parentTaskId != nil {
            return true
        }
        if task.groupId != nil, task.isRecurringSeriesMother == false {
            return true
        }
        return false
    }

    private func loadParentRecurrenceTemplateIfNeeded() async {
        #if canImport(Supabase)
        guard let parentId = editingTask?.parentTaskId else { return }
        do {
            let parent: FamilyTask = try await SupabaseManager.shared.client
                .from("tasks")
                .select()
                .eq("id", value: parentId.uuidString.lowercased())
                .single()
                .execute()
                .value
            let inferred = TaskRecurrenceRule.inferred(from: parent.recurrenceRule, recurrenceInterval: parent.recurrenceInterval)
            selectedRecurrence = inferred
            let customFromParent = max(2, min(365, parent.recurrenceInterval ?? 2))
            recurrenceInterval = inferred == .custom ? customFromParent : 2
            if let end = parent.recurrenceEndDate {
                recurrenceEndDate = end
                showEndDate = true
            }
        } catch {
            #if DEBUG
            print("[CreateTaskView] loadParentRecurrenceTemplateIfNeeded: \(error.localizedDescription)")
            #endif
        }
        #endif
    }

    private func performCreate(householdId: UUID, creatorMembershipId: UUID) async {
        #if canImport(Supabase)
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let now = Date()
            let client = SupabaseManager.shared.client
            let creatorIdLowercased = creatorMembershipId.uuidString.lowercased()
            let recurrence = activeRecurrenceRuleString

            if recurrence == nil {
                let motherId = UUID()
                let singlePayload = TaskInsertPayload(
                    id: motherId,
                    householdId: householdId,
                    creatorId: creatorIdLowercased,
                    parentTaskId: nil,
                    groupId: nil,
                    involvedMemberIds: resolvedInvolvedMemberIds,
                    targetProfileIds: resolvedTargetProfileIds,
                    title: normalizedTitle,
                    description: mergedDescriptionForPayload,
                    status: TaskStatus.new.rawValue,
                    priority: formPriority.rawValue,
                    dueDate: dueDate,
                    endDatetime: resolvedEndDatetime(for: dueDate),
                    durationMinutes: resolvedDurationMinutes(for: dueDate),
                    isAllDay: isAllDay,
                    recurrenceRule: nil,
                    recurrenceEndDate: nil,
                    recurrenceInterval: nil,
                    reminderOffsets: reminderOption.reminderOffsetsMinutes,
                    estimatedCost: estimatedCostMinorUnits,
                    backgroundColor: resolvedBackgroundColorHex(),
                    emergencyPhone: resolvedEmergencyPhoneForPayload(),
                    locationData: resolvedLocationData(),
                    createdAt: now,
                    updatedAt: now
                )
                _ = try await client
                    .from("tasks")
                    .insert(singlePayload)
                    .execute()
                if let synthetic = familyTaskFromInsertPayload(singlePayload) {
                    onAlarmSync?(synthetic)
                }
            } else {
                let motherId = UUID()
                let motherPayload = TaskInsertPayload(
                    id: motherId,
                    householdId: householdId,
                    creatorId: creatorIdLowercased,
                    parentTaskId: nil,
                    groupId: nil,
                    involvedMemberIds: resolvedInvolvedMemberIds,
                    targetProfileIds: resolvedTargetProfileIds,
                    title: normalizedTitle,
                    description: mergedDescriptionForPayload,
                    status: TaskStatus.new.rawValue,
                    priority: formPriority.rawValue,
                    dueDate: dueDate,
                    endDatetime: resolvedEndDatetime(for: dueDate),
                    durationMinutes: resolvedDurationMinutes(for: dueDate),
                    isAllDay: isAllDay,
                    recurrenceRule: recurrence,
                    recurrenceEndDate: resolvedRecurrenceEndDateForPayload(),
                    recurrenceInterval: resolvedRecurrenceIntervalForPayload(),
                    reminderOffsets: reminderOption.reminderOffsetsMinutes,
                    estimatedCost: estimatedCostMinorUnits,
                    backgroundColor: resolvedBackgroundColorHex(),
                    emergencyPhone: resolvedEmergencyPhoneForPayload(),
                    locationData: resolvedLocationData(),
                    createdAt: now,
                    updatedAt: now
                )
                let motherRow: FamilyTask = try await client
                    .from("tasks")
                    .insert(motherPayload)
                    .select()
                    .single()
                    .execute()
                    .value
                if let syntheticMother = familyTaskFromInsertPayload(motherPayload) {
                    onAlarmSync?(syntheticMother)
                }

                let children = await Task.detached(priority: .userInitiated) {
                    RecurrenceEngine.generateInstances(from: motherRow)
                }.value
                if children.isEmpty == false {
                    let childPayloads = children.map { child in
                        TaskInsertPayload(
                            id: child.id,
                            householdId: householdId,
                            creatorId: creatorIdLowercased,
                            parentTaskId: motherRow.id,
                            groupId: nil,
                            involvedMemberIds: resolvedInvolvedMemberIds,
                            targetProfileIds: resolvedTargetProfileIds,
                            title: normalizedTitle,
                            description: mergedDescriptionForPayload,
                            status: TaskStatus.new.rawValue,
                            priority: formPriority.rawValue,
                            dueDate: child.dueDate ?? dueDate,
                            endDatetime: child.endDatetime,
                            durationMinutes: child.durationMinutes,
                            isAllDay: isAllDay,
                            recurrenceRule: nil,
                            recurrenceEndDate: nil,
                            recurrenceInterval: nil,
                            reminderOffsets: reminderOption.reminderOffsetsMinutes,
                            estimatedCost: estimatedCostMinorUnits,
                            backgroundColor: resolvedBackgroundColorHex(),
                            emergencyPhone: resolvedEmergencyPhoneForPayload(),
                            locationData: resolvedLocationData(),
                            createdAt: now,
                            updatedAt: now
                        )
                    }
                    _ = try await client
                        .from("tasks")
                        .insert(childPayloads)
                        .execute()
                    for payload in childPayloads {
                        if let synthetic = familyTaskFromInsertPayload(payload) {
                            onAlarmSync?(synthetic)
                        }
                    }
                }
            }

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

    private static func normalizedStoredHex(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed.uppercased()
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

    private static func priorityForForm(_ priority: TaskPriority) -> TaskPriority {
        switch priority {
        case .urgent, .high:
            return .urgent
        case .normal, .low:
            return .normal
        @unknown default:
            return .normal
        }
    }
}

// MARK: - Reminder

private enum TaskReminderOption: String, CaseIterable, Identifiable {
    case none
    case atTimeOfEvent
    case minutesBefore5
    case minutesBefore15
    case minutesBefore30
    case hourBefore1

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .atTimeOfEvent: return "准时"
        case .minutesBefore5: return "提前5分钟"
        case .minutesBefore15: return "提前15分钟"
        case .minutesBefore30: return "提前30分钟"
        case .hourBefore1: return "提前1小时"
        }
    }

    var reminderOffsetsMinutes: [Int]? {
        switch self {
        case .none: return nil
        case .atTimeOfEvent: return [0]
        case .minutesBefore5: return [5]
        case .minutesBefore15: return [15]
        case .minutesBefore30: return [30]
        case .hourBefore1: return [60]
        }
    }

    init(offsets: [Int]?) {
        guard let offsets, offsets.isEmpty == false else {
            self = .none
            return
        }
        if offsets.contains(0), offsets.allSatisfy({ $0 == 0 }) {
            self = .atTimeOfEvent
            return
        }
        if offsets.contains(5) {
            self = .minutesBefore5
            return
        }
        if offsets.contains(15) {
            self = .minutesBefore15
            return
        }
        if offsets.contains(30) {
            self = .minutesBefore30
            return
        }
        if offsets.contains(60) {
            self = .hourBefore1
            return
        }
        /// 旧版「提前 10 分钟」数据映射为当前最接近项。
        if offsets.contains(10) {
            self = .minutesBefore15
            return
        }
        self = .minutesBefore15
    }
}

private struct AssigneeOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    /// 与 `household_memberships.user_id` 一致：非空表示已注册账号，可出现在「谁去办」人选中。
    let hasRegisteredAccount: Bool

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
    let parentTaskId: UUID?
    let groupId: UUID?
    let involvedMemberIds: [UUID]?
    let targetProfileIds: [UUID]?
    let title: String
    let description: String?
    let status: String
    let priority: String
    let dueDate: Date
    let endDatetime: Date?
    let durationMinutes: Int
    let isAllDay: Bool
    let recurrenceRule: String?
    let recurrenceEndDate: Date?
    let recurrenceInterval: Int?
    let reminderOffsets: [Int]?
    let estimatedCost: Int?
    let backgroundColor: String?
    let emergencyPhone: String?
    let locationData: FamilyTask.LocationData?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case creatorId = "creator_id"
        case parentTaskId = "parent_task_id"
        case groupId = "group_id"
        case involvedMemberIds = "involved_member_ids"
        case targetProfileIds = "target_profile_ids"
        case title
        case description
        case status
        case priority
        case dueDate = "due_date"
        case endDatetime = "end_datetime"
        case durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day"
        case recurrenceRule = "recurrence_rule"
        case recurrenceEndDate = "recurrence_end_date"
        case recurrenceInterval = "recurrence_interval"
        case reminderOffsets = "reminder_offsets"
        case estimatedCost = "estimated_cost"
        case backgroundColor = "background_color"
        case emergencyPhone = "emergency_phone"
        case locationData = "location_data"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(householdId, forKey: .householdId)
        try container.encode(creatorId, forKey: .creatorId)
        if let parentTaskId {
            try container.encode(parentTaskId, forKey: .parentTaskId)
        } else {
            try container.encodeNil(forKey: .parentTaskId)
        }
        try container.encodeIfPresent(groupId, forKey: .groupId)
        if let involvedMemberIds {
            try container.encode(involvedMemberIds, forKey: .involvedMemberIds)
        } else {
            try container.encodeNil(forKey: .involvedMemberIds)
        }
        if let targetProfileIds {
            try container.encode(targetProfileIds, forKey: .targetProfileIds)
        } else {
            try container.encodeNil(forKey: .targetProfileIds)
        }
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(status, forKey: .status)
        try container.encode(priority, forKey: .priority)
        try container.encode(dueDate, forKey: .dueDate)
        if let endDatetime {
            try container.encode(endDatetime, forKey: .endDatetime)
        } else {
            try container.encodeNil(forKey: .endDatetime)
        }
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(isAllDay, forKey: .isAllDay)
        if let recurrenceRule {
            try container.encode(recurrenceRule, forKey: .recurrenceRule)
        } else {
            try container.encodeNil(forKey: .recurrenceRule)
        }
        if let recurrenceEndDate {
            try container.encode(recurrenceEndDate, forKey: .recurrenceEndDate)
        } else {
            try container.encodeNil(forKey: .recurrenceEndDate)
        }
        if let recurrenceInterval {
            try container.encode(recurrenceInterval, forKey: .recurrenceInterval)
        } else {
            try container.encodeNil(forKey: .recurrenceInterval)
        }
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        if let backgroundColor {
            try container.encode(backgroundColor, forKey: .backgroundColor)
        } else {
            try container.encodeNil(forKey: .backgroundColor)
        }
        if let emergencyPhone {
            try container.encode(emergencyPhone, forKey: .emergencyPhone)
        } else {
            try container.encodeNil(forKey: .emergencyPhone)
        }
        if let locationData {
            try container.encode(locationData, forKey: .locationData)
        } else {
            try container.encodeNil(forKey: .locationData)
        }
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct TaskUpdatePayload: Encodable {
    let title: String
    let description: String?
    let involvedMemberIds: [UUID]?
    let targetProfileIds: [UUID]?
    let dueDate: Date
    let endDatetime: Date?
    let durationMinutes: Int
    let isAllDay: Bool
    let recurrenceRule: String?
    let recurrenceEndDate: Date?
    let recurrenceInterval: Int?
    let reminderOffsets: [Int]?
    let estimatedCost: Int?
    let backgroundColor: String?
    let emergencyPhone: String?
    let priority: String
    let locationData: FamilyTask.LocationData?
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case involvedMemberIds = "involved_member_ids"
        case targetProfileIds = "target_profile_ids"
        case dueDate = "due_date"
        case endDatetime = "end_datetime"
        case durationMinutes = "duration_minutes"
        case isAllDay = "is_all_day"
        case recurrenceRule = "recurrence_rule"
        case recurrenceEndDate = "recurrence_end_date"
        case recurrenceInterval = "recurrence_interval"
        case reminderOffsets = "reminder_offsets"
        case estimatedCost = "estimated_cost"
        case backgroundColor = "background_color"
        case emergencyPhone = "emergency_phone"
        case priority
        case locationData = "location_data"
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
        if let targetProfileIds {
            try container.encode(targetProfileIds, forKey: .targetProfileIds)
        } else {
            try container.encodeNil(forKey: .targetProfileIds)
        }
        try container.encode(dueDate, forKey: .dueDate)
        if let endDatetime {
            try container.encode(endDatetime, forKey: .endDatetime)
        } else {
            try container.encodeNil(forKey: .endDatetime)
        }
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(isAllDay, forKey: .isAllDay)
        if let recurrenceRule {
            try container.encode(recurrenceRule, forKey: .recurrenceRule)
        } else {
            try container.encodeNil(forKey: .recurrenceRule)
        }
        if let recurrenceEndDate {
            try container.encode(recurrenceEndDate, forKey: .recurrenceEndDate)
        } else {
            try container.encodeNil(forKey: .recurrenceEndDate)
        }
        if let recurrenceInterval {
            try container.encode(recurrenceInterval, forKey: .recurrenceInterval)
        } else {
            try container.encodeNil(forKey: .recurrenceInterval)
        }
        try container.encodeIfPresent(reminderOffsets, forKey: .reminderOffsets)
        try container.encodeIfPresent(estimatedCost, forKey: .estimatedCost)
        if let backgroundColor {
            try container.encode(backgroundColor, forKey: .backgroundColor)
        } else {
            try container.encodeNil(forKey: .backgroundColor)
        }
        if let emergencyPhone {
            try container.encode(emergencyPhone, forKey: .emergencyPhone)
        } else {
            try container.encodeNil(forKey: .emergencyPhone)
        }
        try container.encode(priority, forKey: .priority)
        if let locationData {
            try container.encode(locationData, forKey: .locationData)
        } else {
            try container.encodeNil(forKey: .locationData)
        }
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

private extension CreateTaskView {
    /// 无重复规则时强制为 `nil`；未勾选「指定重复结束日期」时为 `nil`。
    func resolvedRecurrenceEndDateForPayload() -> Date? {
        guard selectedRecurrence != .none else { return nil }
        guard showEndDate else { return nil }
        return Calendar.current.startOfDay(for: recurrenceEndDate)
    }

    /// 无重复规则时强制为 `nil`；`custom` 写入间隔天数字，其余重复写 `1`。
    func resolvedRecurrenceIntervalForPayload() -> Int? {
        guard selectedRecurrence != .none else { return nil }
        if selectedRecurrence == .custom {
            return recurrenceInterval
        }
        return 1
    }

    /// 由开始时间与任务时长推算 `end_datetime`；全天任务不写结束时间。
    func resolvedEndDatetime(for occurrenceDue: Date) -> Date? {
        guard isAllDay == false else { return nil }
        let minutes = Self.durationMinutes(from: durationPickerDate)
        return occurrenceDue.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 写入 `tasks.duration_minutes`（NOT NULL）。
    func resolvedDurationMinutes(for occurrenceDue: Date) -> Int {
        Self.durationMinutes(from: durationPickerDate)
    }

    static func makeDurationPickerDate(minutes: Int) -> Date {
        let clamped = max(1, minutes)
        let hours = clamped / 60
        let remainder = clamped % 60
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        return calendar.date(
            bySettingHour: hours,
            minute: remainder,
            second: 0,
            of: anchor
        ) ?? anchor
    }

    static func durationMinutes(from pickerDate: Date) -> Int {
        let calendar = Calendar.current
        let hours = calendar.component(.hour, from: pickerDate)
        let minutes = calendar.component(.minute, from: pickerDate)
        return max(1, hours * 60 + minutes)
    }

    func resolvedBackgroundColorHex() -> String? {
        guard let raw = selectedBackgroundHex?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false else {
            return nil
        }
        return raw.uppercased()
    }

    func resolvedLocationData() -> FamilyTask.LocationData? {
        let trimmed = locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return FamilyTask.LocationData(name: trimmed, address: nil, latitude: nil, longitude: nil)
    }

    func resolvedEmergencyPhoneForPayload() -> String? {
        let collapsed = emergencyPhone.filter { character in
            character.isWhitespace == false && character.isNewline == false
        }
        return collapsed.isEmpty ? nil : collapsed
    }

    /// 「所有人」写入 `nil`；否则写入所选 membership id 列表。
    var resolvedInvolvedMemberIds: [UUID]? {
        if selectedAssigneeIds.isEmpty {
            return nil
        }
        return Array(selectedAssigneeIds)
    }

    /// 「为了谁」未选具体档案时写入 `nil`；否则写入 `family_profiles.id` 列表（`tasks.target_profile_ids`）。
    var resolvedTargetProfileIds: [UUID]? {
        if selectedTargetProfileIds.isEmpty {
            return nil
        }
        return Array(selectedTargetProfileIds)
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

    /// 插入成功后用于本地闹钟同步（字段与写入 payload 一致）。
    func familyTaskFromInsertPayload(_ payload: TaskInsertPayload) -> FamilyTask? {
        guard let creatorUUID = UUID(uuidString: payload.creatorId) else { return nil }
        guard let status = TaskStatus(rawValue: payload.status) else { return nil }
        let priority = TaskPriority(rawValue: payload.priority) ?? .normal
        return FamilyTask(
            id: payload.id,
            householdId: payload.householdId,
            creatorId: creatorUUID,
            parentTaskId: payload.parentTaskId,
            groupId: payload.groupId,
            originalDueDate: nil,
            involvedMemberIds: payload.involvedMemberIds,
            targetProfileId: nil,
            targetProfileIds: payload.targetProfileIds,
            targetSubject: nil,
            title: payload.title,
            description: payload.description,
            originalPrompt: nil,
            attachmentUrls: nil,
            externalContacts: nil,
            locationData: payload.locationData,
            externalSyncRefs: nil,
            alarmSetBy: nil,
            status: status,
            priority: priority,
            dueDate: payload.dueDate,
            endDatetime: payload.endDatetime,
            durationMinutes: payload.durationMinutes,
            isAllDay: payload.isAllDay,
            recurrenceRule: payload.recurrenceRule,
            recurrenceEndDate: payload.recurrenceEndDate,
            recurrenceInterval: payload.recurrenceInterval,
            reminderOffsets: payload.reminderOffsets,
            estimatedCost: payload.estimatedCost,
            backgroundColor: payload.backgroundColor,
            emergencyPhone: payload.emergencyPhone,
            createdAt: payload.createdAt,
            updatedAt: payload.updatedAt
        )
    }
}

#Preview {
    CreateTaskView()
        .environmentObject(AppRouter())
}
