import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

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

    let onSaveSuccess: ((Date) -> Void)?

    init(onSaveSuccess: ((Date) -> Void)? = nil) {
        self.onSaveSuccess = onSaveSuccess
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
            .navigationTitle("新建任务")
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
                focusedField = .title
            }
        }
        .task {
            await loadAssignees()
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

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        #if canImport(Supabase)
        do {
            let now = Date()
            let membershipContext = creatorMembershipId
            let creatorIdLowercased = membershipContext.uuidString.lowercased()

            let payload = TaskInsertPayload(
                id: UUID(),
                householdId: householdId,
                creatorId: creatorIdLowercased,
                involvedMemberIds: resolvedInvolvedMemberIds,
                title: normalizedTitle,
                description: mergedDescriptionForPayload,
                status: TaskStatus.new.rawValue,
                priority: TaskPriority.normal.rawValue,
                dueDate: dueDate,
                isAllDay: isAllDay,
                recurrenceRule: repeatOption.recurrenceRule,
                reminderOffsets: reminderOption.reminderOffsetsMinutes,
                estimatedCost: estimatedCostMinorUnits,
                createdAt: now,
                updatedAt: now
            )

            _ = try await SupabaseManager.shared.client
                .from("tasks")
                .insert(payload)
                .execute()

            onSaveSuccess?(dueDate)
            dismiss()
        } catch {
            #if DEBUG
            print("[CreateTaskView] saveTask failed: \(error.localizedDescription)")
            #endif
            errorMessage = "任务保存失败：\(error.localizedDescription)"
        }
        #else
        errorMessage = "当前构建环境未包含 Supabase SDK。"
        #endif
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
