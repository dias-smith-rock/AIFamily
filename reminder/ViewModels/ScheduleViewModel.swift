import Foundation
import Combine

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var tasks: [FamilyTask] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService
    private var currentHouseholdId: UUID?

    init(taskService: TaskDataService) {
        self.taskService = taskService
    }

    func setHouseholdContext(_ householdId: UUID?) {
        currentHouseholdId = householdId
    }

    func loadTasks() async {
        guard let householdId = currentHouseholdId else {
            tasks = []
            errorMessage = "当前未选择家庭。"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            tasks = try await taskService.fetchTasks(in: householdId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(_ task: FamilyTask) async {
        guard let householdId = currentHouseholdId else {
            errorMessage = "当前未选择家庭。"
            return
        }
        guard task.householdId == householdId else {
            errorMessage = "任务写入失败：家庭上下文不一致。"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let createdTask = try await taskService.createTask(task)
            tasks.append(createdTask)
            tasks.sort { lhs, rhs in
                (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTask(_ task: FamilyTask) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let updatedTask = try await taskService.updateTask(task)
            guard let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) else {
                await loadTasks()
                return
            }
            tasks[index] = updatedTask
            tasks.sort { lhs, rhs in
                (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateTaskStatus(taskId: UUID, to status: TaskStatus) async {
        guard let currentTask = tasks.first(where: { $0.id == taskId }) else { return }
        var updatedTask = currentTask
        updatedTask.status = status
        await updateTask(updatedTask)
    }

    /// 成员详情页状态机：仅 PATCH `status`，避免整行写入与并发覆盖。
    func patchTaskStatus(taskId: UUID, to status: TaskStatus) async throws -> FamilyTask {
        errorMessage = nil

        let updated = try await taskService.patchTaskStatus(taskId: taskId, to: status)
        if let index = tasks.firstIndex(where: { $0.id == updated.id }) {
            tasks[index] = updated
        } else {
            tasks.append(updated)
        }
        tasks.sort { lhs, rhs in
            (lhs.dueDate ?? lhs.createdAt) < (rhs.dueDate ?? rhs.createdAt)
        }
        return updated
    }
}
