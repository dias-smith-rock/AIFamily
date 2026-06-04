import Foundation

@MainActor
final class ForegroundLocationPersistEligibility {
    static let shared = ForegroundLocationPersistEligibility()

    var canPersist = false

    private init() {}
}
