import Foundation

@main struct MatchingTests {
    static func main() {
        let one = FamilyProfile(id: UUID(), name: "小明", displayName: "小明", primaryMembership: nil)
        let two = FamilyProfile(id: UUID(), name: "小明", displayName: "小明", primaryMembership: nil)
        assert(AIParticipantHintMatcher.match(hints: ["小明"], profiles: [one], memberships: []).targetProfileIds == [one.id])
        assert(AIParticipantHintMatcher.match(hints: ["小明"], profiles: [one,two], memberships: []).targetProfileIds.isEmpty)
        assert(AIParticipantHintMatcher.match(hints: ["小"], profiles: [one], memberships: []).targetProfileIds.isEmpty)
        assert(AIParticipantHintMatcher.match(hints: ["全家"], profiles: [one], memberships: []).targetProfileIds.isEmpty)
        let sally = FamilyProfile(id: UUID(), name: "Sally", displayName: "Sally", primaryMembership: nil)
        assert(AIParticipantHintMatcher.match(hints: ["Sally"], profiles: [sally], memberships: []).targetProfileIds == [sally.id])
        assert(AIParticipantHintMatcher.match(hints: ["Sally", "whole family"], profiles: [sally], memberships: []).targetProfileIds.isEmpty)
        print("Participant matching: 6 checks passed")
    }
}
