import SwiftUI

/// List 模式：任务平铺列表（后续可接入筛选、分组与导航至详情）。
struct TaskModeListView: View {
    @ObservedObject var viewModel: ScheduleViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("正在加载任务...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView {
                    Label("加载失败", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.tasks.isEmpty {
                ContentUnavailableView {
                    Label("暂无任务", systemImage: "checklist")
                } description: {
                    Text("创建任务后将显示在此列表。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.tasks.sorted(by: { taskDisplayDate($0) < taskDisplayDate($1) })) { task in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(task.title)
                                .font(.body.weight(.semibold))
                            Text(listSubtitle(for: task))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func taskDisplayDate(_ task: FamilyTask) -> Date {
        task.dueDate ?? task.originalDueDate ?? task.createdAt
    }

    private func listSubtitle(for task: FamilyTask) -> String {
        let date = taskDisplayDate(task)
        if task.isAllDay {
            return date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
        }
        return date.formatted(date: .omitted, time: .shortened)
    }
}
