import Foundation

enum TrackedDevicePINSync {
    static func applyFromServer(
        using service: TrackedDevicePairingService = SupabaseTrackedDevicePairingService()
    ) async {
        do {
            let pin = try await service.syncOwnPIN()
            if let pin, TrackedDevicePINStore.isValidFormat(pin) {
                TrackedDevicePINStore.savePIN(pin)
            } else {
                TrackedDevicePINStore.clear()
            }
        } catch {
            return
        }
    }
}
