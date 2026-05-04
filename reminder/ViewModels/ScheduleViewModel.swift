import Foundation
import Combine

@MainActor
final class ScheduleViewModel: ObservableObject {
    @Published private(set) var tasks: [FamilyTask] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let taskService: TaskDataService

    init(taskService: TaskDataService) {
        self.taskService = taskService
    }

    func loadTasks() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            tasks = try await taskService.fetchTasks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createTask(_ task: FamilyTask) async {
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
}
