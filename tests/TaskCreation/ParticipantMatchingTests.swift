import Foundation

@main struct MatchingTests {
    static func main() {
        let one = FamilyProfile(id: UUID(), name: "小明", displayName: "小明", primaryMembership: nil)
        let two = FamilyProfile(id: UUID(), name: "小明", displayName: "小明", primaryMembership: nil)
        assert(AIParticipantHintMatcher.match(hints: ["小明"], profiles: [one], memberships: []).targetProfileIds == [one.id])
        assert(AIParticipantHintMatcher.match(hints: ["小明"], profiles: [one,two], memberships: []).targetProfileIds.isEmpty)
        assert(AIParticipantHintMatcher.match(hints: ["小"], profiles: [one], memberships: []).targetProfileIds.isEmpty)
        assert(AIParticipantHintMatcher.match(hints: ["全家"], profiles: [one], memberships: []).targetProfileIds.isEmpty)
        print("Participant matching: 4 checks passed")
    }
}
