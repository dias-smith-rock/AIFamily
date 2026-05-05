import SwiftUI

#if canImport(Supabase)
import Supabase
#endif

struct CreateTaskView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appRouter: AppRouter

    @State private var title = ""
    @State private var dueDate = Date()
    @State private var isAllDay = false
    @State private var selectedAssigneeIds: Set<UUID> = []
    @State private var assignees: [AssigneeOption] = []
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSaveSuccess: ((Date) -> Void)?

    init(onSaveSuccess: ((Date) -> Void)? = nil) {
        self.onSaveSuccess = onSaveSuccess
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("任务内容") {
                    TextField("准备做什么？", text: $title, axis: .vertical)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(2...4)
                }

                Section("任务细节") {
                    Toggle("全天", isOn: $isAllDay)

                    DatePicker(
                        isAllDay ? "执行日期" : "执行时间",
                        selection: $dueDate,
                        displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute]
                    )

                    Menu {
                        Button {
                            selectedAssigneeIds = []
                        } label: {
                            if selectedAssigneeIds.isEmpty {
                                Label("所有人", systemImage: "checkmark")
                            } else {
                                Text("所有人")
                            }
                        }

                        Divider()

                        ForEach(assignees) { value in
                            Button {
                                toggleAssignee(value.id)
                            } label: {
                                if selectedAssigneeIds.contains(value.id) {
                                    Label(value.name, systemImage: "checkmark")
                                } else {
                                    Text(value.name)
                                }
                            }
                        }
                    } label: {
                        HStack {
                            Text("指派给")
                            Spacer()
                            Text(assigneeSummary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section("补充说明（可选）") {
                    TextField("添加备注...", text: $note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(AppTheme.FontToken.caption)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task {
                            await saveTask()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if isSaving {
                                ProgressView()
                            } else {
                                Text("保存")
                                    .font(AppTheme.FontToken.bodyStrong)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(normalizedTitle.isEmpty || isSaving)
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
            }
        }
        .task {
            await loadAssignees()
        }
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
            let payload = TaskInsertPayload(
                id: UUID(),
                householdId: householdId,
                creatorId: creatorMembershipId,
                involvedMemberIds: resolvedInvolvedMemberIds,
                title: normalizedTitle,
                description: normalizedNote,
                status: TaskStatus.new.rawValue,
                priority: TaskPriority.normal.rawValue,
                dueDate: dueDate,
                isAllDay: isAllDay,
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

    private var normalizedNote: String? {
        let value = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private struct AssigneeOption: Identifiable, Equatable {
    let id: UUID
    let name: String
}

private struct TaskInsertPayload: Encodable {
    let id: UUID
    let householdId: UUID
    let creatorId: UUID
    let involvedMemberIds: [UUID]?
    let title: String
    let description: String?
    let status: String
    let priority: String
    let dueDate: Date
    let isAllDay: Bool
    let createdAt: Date
    let updatedAt: Date
}

private extension CreateTaskView {
    /// 「所有人」写入 `nil`，由查询端按家庭维度展示，后续新成员自动包含；具体名单则写入非空数组。
    var resolvedInvolvedMemberIds: [UUID]? {
        if selectedAssigneeIds.isEmpty {
            return nil
        }
        return Array(selectedAssigneeIds)
    }
}

#Preview {
    CreateTaskView()
        .environmentObject(AppRouter())
}
