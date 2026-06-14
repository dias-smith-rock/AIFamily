import Foundation

#if DEBUG && canImport(Supabase)
import Supabase
#endif

#if DEBUG
/// DEBUG 专用：游客 session / 归档 / 路由状态诊断（前缀 `[GuestDiag]`）。
@MainActor
enum GuestSessionDiagnostics {
    struct MembershipSummary: Sendable {
        let rawCount: Int
        let filteredCount: Int
        let droppedBySelectable: Int
        let droppedByArchived: Int
    }

    struct RefreshSummary: Sendable {
        let activeMembershipCount: Int
        let optionsCount: Int
        let totalMembershipCount: Int
    }

    static func log(
        _ label: String,
        appRouter: AppRouter,
        membershipSummary: MembershipSummary? = nil,
        refreshSummary: RefreshSummary? = nil,
        note: String? = nil
    ) {
        print(format(label: label, appRouter: appRouter, membershipSummary: membershipSummary, refreshSummary: refreshSummary, note: note))
    }

    static func logAsync(_ label: String, appRouter: AppRouter, note: String? = nil) async {
        let line = await formatAsync(label: label, appRouter: appRouter, note: note)
        print(line)
    }

    private static func format(
        label: String,
        appRouter: AppRouter,
        membershipSummary: MembershipSummary?,
        refreshSummary: RefreshSummary?,
        note: String?
    ) -> String {
        var parts: [String] = ["[GuestDiag]", "label=\(label)"]
        parts.append(contentsOf: appRouterFields(appRouter))
        parts.append(contentsOf: archiveFields())
        parts.append(contentsOf: keychainSessionFields())
        if let membershipSummary {
            parts.append(
                "memberships raw=\(membershipSummary.rawCount) filtered=\(membershipSummary.filteredCount) droppedSelectable=\(membershipSummary.droppedBySelectable) droppedArchived=\(membershipSummary.droppedByArchived)"
            )
        }
        if let refreshSummary {
            parts.append(
                "refresh active=\(refreshSummary.activeMembershipCount) total=\(refreshSummary.totalMembershipCount) options=\(refreshSummary.optionsCount)"
            )
        }
        if let note, note.isEmpty == false {
            parts.append("note=\(note)")
        }
        return parts.joined(separator: " ")
    }

    private static func formatAsync(label: String, appRouter: AppRouter, note: String?) async -> String {
        var parts: [String] = ["[GuestDiag]", "label=\(label)"]
        parts.append(contentsOf: appRouterFields(appRouter))
        parts.append(contentsOf: archiveFields())
        parts.append(contentsOf: keychainSessionFields())
        #if canImport(Supabase)
        parts.append(contentsOf: await authSessionFields())
        #endif
        if let note, note.isEmpty == false {
            parts.append("note=\(note)")
        }
        return parts.joined(separator: " ")
    }

    private static func appRouterFields(_ appRouter: AppRouter) -> [String] {
        [
            "router.authUserId=\(uuidString(appRouter.authUserId))",
            "router.isAnonymous=\(appRouter.isAnonymousUser)",
            "router.appState=\(appRouter.appState.diagName)",
            "router.selectedHouseholdId=\(uuidString(appRouter.selectedHouseholdId))",
            "router.selectableCount=\(appRouter.selectableHouseholds.count)",
            "router.skipNextRefresh=\(appRouter.guestDiagnosticsWillSkipNextLoginBootstrapRefresh)",
            "router.hasCompletedBootstrap=\(appRouter.hasCompletedAuthBootstrap)",
            "router.offlineSnapshot=\(hasOfflineSnapshot())",
        ]
    }

    private static func archiveFields() -> [String] {
        var parts: [String] = []
        if let guest = GuestSessionArchive.load() {
            parts += [
                "guestArchive.present=true",
                "guestArchive.userId=\(guest.userId.uuidString.lowercased())",
                "guestArchive.accessPrefix=\(tokenPrefix(guest.accessToken))",
            ]
        } else {
            parts.append("guestArchive.present=false")
        }
        if let formal = FormalSessionArchive.load() {
            parts += [
                "formalArchive.present=true",
                "formalArchive.userId=\(formal.userId.uuidString.lowercased())",
                "formalArchive.accessPrefix=\(tokenPrefix(formal.accessToken))",
            ]
        } else {
            parts.append("formalArchive.present=false")
        }
        return parts
    }

    private static func keychainSessionFields() -> [String] {
        #if canImport(Supabase)
        guard let session = SupabaseManager.shared.client.auth.currentSession else {
            return ["keychainSession=nil"]
        }
        return sessionFields(prefix: "keychainSession", session: session)
        #else
        return ["keychainSession=unavailable"]
        #endif
    }

    #if canImport(Supabase)
    private static func authSessionFields() async -> [String] {
        do {
            let session = try await SupabaseManager.shared.client.auth.session
            return sessionFields(prefix: "authSession", session: session)
        } catch {
            return ["authSession=error(\(error.localizedDescription))"]
        }
    }

    private static func sessionFields(prefix: String, session: Session) -> [String] {
        [
            "\(prefix).userId=\(session.user.id.uuidString.lowercased())",
            "\(prefix).isAnonymous=\(session.user.isAnonymous)",
            "\(prefix).accessPrefix=\(tokenPrefix(session.accessToken))",
            "\(prefix).refreshPrefix=\(tokenPrefix(session.refreshToken))",
            "\(prefix).expiresAt=\(session.expiresAt)",
        ]
    }
    #endif

    private static func hasOfflineSnapshot() -> Bool {
        UserDefaults.standard.data(forKey: AppRouter.offlineHouseholdSnapshotKey) != nil
    }

    private static func uuidString(_ id: UUID?) -> String {
        id?.uuidString.lowercased() ?? "nil"
    }

    private static func tokenPrefix(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "empty" }
        return String(trimmed.prefix(8))
    }
}

private extension AppRouter.AppState {
    var diagName: String {
        switch self {
        case .unauthenticated: return "unauthenticated"
        case .orgRouting: return "orgRouting"
        case .householdSelection: return "householdSelection"
        case .pendingApproval: return "pendingApproval"
        case .activeMember: return "activeMember"
        }
    }
}

#else

@MainActor
enum GuestSessionDiagnostics {
    struct MembershipSummary: Sendable {
        let rawCount: Int
        let filteredCount: Int
        let droppedBySelectable: Int
        let droppedByArchived: Int
    }

    struct RefreshSummary: Sendable {
        let activeMembershipCount: Int
        let optionsCount: Int
        let totalMembershipCount: Int
    }

    static func log(
        _ label: String,
        appRouter: AppRouter,
        membershipSummary: MembershipSummary? = nil,
        refreshSummary: RefreshSummary? = nil,
        note: String? = nil
    ) {}

    static func logAsync(_ label: String, appRouter: AppRouter, note: String? = nil) async {}
}

#endif
