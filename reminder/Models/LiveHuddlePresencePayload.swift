import Foundation

/// Live Huddle Presence 状态（仅存于 Realtime，不写数据库）。
struct LiveHuddlePresencePayload: Codable, Hashable, Sendable {
    let userId: UUID
    let membershipId: UUID
    let status: String

    init(userId: UUID, membershipId: UUID, status: String = "active") {
        self.userId = userId
        self.membershipId = membershipId
        self.status = status
    }
}
