import Foundation

/// 缓存优先刷新：网络结果与当前展示内容等价时跳过赋值，避免无意义重绘。
enum CacheFirstContent {
    static func areTasksEquivalent(_ lhs: [FamilyTask], _ rhs: [FamilyTask]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        if lhs.isEmpty { return true }

        var map = [UUID: FamilyTask](minimumCapacity: lhs.count)
        for task in lhs {
            // 异常重复 id 时退回排序全量比较
            if map.updateValue(task, forKey: task.id) != nil {
                return sortedTasks(lhs) == sortedTasks(rhs)
            }
        }
        for task in rhs {
            guard map[task.id] == task else { return false }
        }
        return true
    }

    private static func sortedTasks(_ tasks: [FamilyTask]) -> [FamilyTask] {
        tasks.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
