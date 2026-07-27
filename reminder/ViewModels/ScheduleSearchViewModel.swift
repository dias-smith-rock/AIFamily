import Foundation
import Combine

@MainActor
final class ScheduleSearchViewModel: ObservableObject {
    struct ResultItem: Identifiable, Equatable {
        enum Kind: Equatable {
            case scheduledTask
            case todo
            case ledger
            case member
        }

        let id: UUID
        let kind: Kind
        let title: String
        let subtitle: String
        let householdId: UUID
        let householdName: String
        let task: FamilyTask?
        let transaction: LedgerTransaction?
        let profile: FamilyProfile?
    }

    @Published var query = ""
    @Published private(set) var taskResults: [ResultItem] = []
    @Published private(set) var todoResults: [ResultItem] = []
    @Published private(set) var ledgerResults: [ResultItem] = []
    @Published private(set) var memberResults: [ResultItem] = []
    @Published private(set) var isSearching = false

    private let taskService: TaskDataService
    private let ledgerService: LedgerDataService
    private let membershipService: HouseholdMembershipDataService
    private var searchTask: Task<Void, Never>?

    init(
        taskService: TaskDataService,
        ledgerService: LedgerDataService,
        membershipService: HouseholdMembershipDataService
    ) {
        self.taskService = taskService
        self.ledgerService = ledgerService
        self.membershipService = membershipService
    }

    func scheduleSearch(householdIds: [UUID], householdNames: [UUID: String]) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, householdIds.isEmpty == false else {
            clearResults()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard Task.isCancelled == false else { return }
            await self?.runSearch(
                query: trimmed,
                householdIds: householdIds,
                householdNames: householdNames
            )
        }
    }

    private func clearResults() {
        taskResults = []
        todoResults = []
        ledgerResults = []
        memberResults = []
        isSearching = false
    }

    private func runSearch(
        query: String,
        householdIds: [UUID],
        householdNames: [UUID: String]
    ) async {
        isSearching = true
        defer { isSearching = false }

        let needle = query.lowercased()
        var tasks: [ResultItem] = []
        var todos: [ResultItem] = []
        var ledger: [ResultItem] = []
        var members: [ResultItem] = []

        for householdId in householdIds {
            let name = householdNames[householdId]
                ?? AppLocalized.localized(L10n.Family.unnamedGroup)
            do {
                let fetched = try await taskService.fetchTasks(in: householdId)
                for task in fetched {
                    let title = task.title.lowercased()
                    let note = (task.description ?? "").lowercased()
                    guard title.contains(needle) || note.contains(needle) else { continue }
                    let item = ResultItem(
                        id: task.id,
                        kind: task.isFlexibleTodoCandidate ? .todo : .scheduledTask,
                        title: task.title,
                        subtitle: note.isEmpty ? name : (task.description ?? name),
                        householdId: householdId,
                        householdName: name,
                        task: task,
                        transaction: nil,
                        profile: nil
                    )
                    if task.isFlexibleTodoCandidate {
                        todos.append(item)
                    } else if task.isScheduledCalendarTask {
                        tasks.append(item)
                    }
                }
            } catch {
                #if DEBUG
                print("[ScheduleSearch] tasks failed \(error.localizedDescription)")
                #endif
            }

            do {
                let txs = try await ledgerService.fetchTransactions(in: householdId)
                for tx in txs {
                    let haystack = [
                        tx.note ?? "",
                        tx.categoryNameSnapshot,
                        String(tx.amount),
                        tx.currency
                    ].joined(separator: " ").lowercased()
                    guard haystack.contains(needle) else { continue }
                    ledger.append(
                        ResultItem(
                            id: tx.id,
                            kind: .ledger,
                            title: tx.note?.isEmpty == false ? (tx.note ?? tx.categoryNameSnapshot) : tx.categoryNameSnapshot,
                            subtitle: "\(tx.currency) \(tx.amount) · \(name)",
                            householdId: householdId,
                            householdName: name,
                            task: nil,
                            transaction: tx,
                            profile: nil
                        )
                    )
                }
            } catch {
                #if DEBUG
                print("[ScheduleSearch] ledger failed \(error.localizedDescription)")
                #endif
            }

            do {
                let roster = try await membershipService.fetchMemberRoster(in: householdId, activeOnly: true)
                for profile in roster.profiles {
                    let display = profile.displayName.lowercased()
                    guard display.contains(needle) else { continue }
                    members.append(
                        ResultItem(
                            id: profile.id,
                            kind: .member,
                            title: profile.displayName,
                            subtitle: name,
                            householdId: householdId,
                            householdName: name,
                            task: nil,
                            transaction: nil,
                            profile: profile
                        )
                    )
                }
            } catch {
                #if DEBUG
                print("[ScheduleSearch] members failed \(error.localizedDescription)")
                #endif
            }
        }

        guard Task.isCancelled == false else { return }
        taskResults = tasks
        todoResults = todos
        ledgerResults = ledger
        memberResults = members
    }
}
