import Foundation

#if canImport(Supabase)
import Supabase
#endif

protocol TrackedDevicePairingService: Sendable {
    func createPairingNonce(
        householdId: UUID,
        managerMembershipId: UUID,
        targetProfileId: UUID
    ) async throws -> String

    func claimPairingNonce(_ code: String) async throws -> UUID

    func fetchPIN(householdId: UUID, targetProfileId: UUID) async throws -> String?

    func setPIN(householdId: UUID, targetProfileId: UUID, pin: String) async throws

    func syncOwnPIN() async throws -> String?

    func reportOwnPIN(_ pin: String) async throws

    func reportOwnDeviceModel(_ model: String) async throws

    func isPairingNonceConsumed(_ code: String) async throws -> Bool

    func fetchAdminBindingSnapshot(
        householdId: UUID,
        targetProfileId: UUID
    ) async throws -> TrackedDeviceAdminBindingSnapshot
}

struct TrackedDeviceAdminBindingSnapshot: Equatable, Sendable {
    var isBound: Bool
    var nickname: String?
    var deviceModel: String?
    var boundAt: Date?
    var lastReportedAt: Date?
    var batteryLevel: Int?
    var isCharging: Bool?
    var addressName: String?

    static let unbound = TrackedDeviceAdminBindingSnapshot(
        isBound: false,
        nickname: nil,
        deviceModel: nil,
        boundAt: nil,
        lastReportedAt: nil,
        batteryLevel: nil,
        isCharging: nil,
        addressName: nil
    )
}

struct SupabaseTrackedDevicePairingService: TrackedDevicePairingService {
    private let provider: SupabaseClientProviding

    init(provider: SupabaseClientProviding = SupabaseProvider()) {
        self.provider = provider
    }

    func createPairingNonce(
        householdId: UUID,
        managerMembershipId: UUID,
        targetProfileId: UUID
    ) async throws -> String {
        #if canImport(Supabase)
        do {
            let response = try await provider.client
                .rpc(
                    "create_tracked_device_pairing_nonce",
                    params: CreateTrackedDevicePairingNonceParams(
                        pHouseholdId: householdId,
                        pManagerMembershipId: managerMembershipId,
                        pTargetProfileId: targetProfileId
                    )
                )
                .execute()
            if let text = String(data: response.data, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                .trimmingCharacters(in: .whitespacesAndNewlines),
               text.isEmpty == false {
                return text.uppercased()
            }
            throw TrackedDevicePairingError.backendMigrationRequired
        } catch let error as TrackedDevicePairingError {
            throw error
        } catch {
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func claimPairingNonce(_ code: String) async throws -> UUID {
        #if canImport(Supabase)
        let normalized = TrackedDevicePairingCode.parse(code)
            ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard normalized.count == 6 else {
            TrackedDevicePairingLogger.event("claim_reject_local_code", code: code, detail: "normalized=\(normalized)")
            throw TrackedDevicePairingError.invalidCode
        }
        let userId: UUID
        do {
            userId = try await provider.client.auth.session.user.id
        } catch {
            TrackedDevicePairingLogger.failure(error, stage: "claim_session", code: normalized)
            throw TrackedDevicePairingError.unauthenticated
        }
        TrackedDevicePairingLogger.event(
            "claim_rpc_start",
            code: normalized,
            userId: userId,
            detail: "rpc=claim_tracked_device_pairing_nonce p_pin=empty model=\(TrackedDeviceHardware.marketingName)"
        )
        do {
            return try await executeClaim(
                params: ClaimTrackedDevicePairingNonceParams(
                    pNonce: normalized,
                    pUserId: userId,
                    pPin: "",
                    pDeviceModel: TrackedDeviceHardware.marketingName
                ),
                code: normalized,
                userId: userId
            )
        } catch {
            let mapped = TrackedDevicePairingSupport.mapClaimError(error)
            if case .backendMigrationRequired = mapped {
                TrackedDevicePairingLogger.event("claim_rpc_retry_legacy", code: normalized)
                return try await executeClaim(
                    params: ClaimTrackedDevicePairingNonceLegacyParams(
                        pNonce: normalized,
                        pUserId: userId,
                        pPin: ""
                    ),
                    code: normalized,
                    userId: userId
                )
            }
            TrackedDevicePairingLogger.failure(error, stage: "claim_rpc", code: normalized)
            throw mapped
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    #if canImport(Supabase)
    private func executeClaim<Params: Encodable>(
        params: Params,
        code: String,
        userId: UUID
    ) async throws -> UUID {
        let response = try await provider.client
            .rpc("claim_tracked_device_pairing_nonce", params: params)
            .execute()
        let rawBody = String(data: response.data, encoding: .utf8) ?? "<non-utf8>"
        TrackedDevicePairingLogger.event(
            "claim_rpc_ok_body",
            code: code,
            userId: userId,
            detail: "bytes=\(response.data.count) body=\(rawBody)"
        )
        if let uuid = try? JSONDecoder().decode(UUID.self, from: response.data) {
            return uuid
        }
        if let raw = String(data: response.data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t")),
           let uuid = UUID(uuidString: raw) {
            return uuid
        }
        throw TrackedDevicePairingError.invalidCode
    }
    #endif

    func fetchPIN(householdId: UUID, targetProfileId: UUID) async throws -> String? {
        #if canImport(Supabase)
        do {
            let response = try await provider.client
                .rpc(
                    "get_tracked_device_pin",
                    params: GetTrackedDevicePINParams(
                        pHouseholdId: householdId,
                        pTargetProfileId: targetProfileId
                    )
                )
                .execute()
            return Self.decodeOptionalPIN(from: response.data)
        } catch {
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func setPIN(householdId: UUID, targetProfileId: UUID, pin: String) async throws {
        #if canImport(Supabase)
        let normalizedPIN = TrackedDevicePINStore.normalize(pin)
        guard TrackedDevicePINStore.isAcceptableInput(normalizedPIN) else {
            throw TrackedDevicePairingError.invalidPIN
        }
        do {
            _ = try await provider.client
                .rpc(
                    "set_tracked_device_pin",
                    params: SetTrackedDevicePINParams(
                        pHouseholdId: householdId,
                        pTargetProfileId: targetProfileId,
                        pPin: normalizedPIN
                    )
                )
                .execute()
            TrackedDevicePairingLogger.event(
                "set_pin_ok",
                detail: "household=\(householdId.uuidString) profile=\(targetProfileId.uuidString) pin_len=\(normalizedPIN.count)"
            )
        } catch {
            TrackedDevicePairingLogger.failure(error, stage: "set_pin")
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func syncOwnPIN() async throws -> String? {
        #if canImport(Supabase)
        do {
            let response = try await provider.client
                .rpc("sync_own_tracked_device_pin")
                .execute()
            return Self.decodeOptionalPIN(from: response.data)
        } catch {
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func isPairingNonceConsumed(_ code: String) async throws -> Bool {
        #if canImport(Supabase)
        let normalized = TrackedDevicePairingCode.parse(code)
            ?? code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do {
            let row: TrackedDevicePairingNonceConsumedRow = try await provider.client
                .from("tracked_device_pairing_nonces")
                .select("consumed_at")
                .eq("nonce", value: normalized)
                .single()
                .execute()
                .value
            return row.isConsumed
        } catch {
            TrackedDevicePairingLogger.failure(error, stage: "watch_nonce_select", code: normalized)
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        _ = code
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func fetchAdminBindingSnapshot(
        householdId: UUID,
        targetProfileId: UUID
    ) async throws -> TrackedDeviceAdminBindingSnapshot {
        #if canImport(Supabase)
        TrackedDevicePairingLogger.event(
            "admin_snapshot_start",
            detail: "household=\(householdId.uuidString.lowercased()) profile=\(targetProfileId.uuidString.lowercased())"
        )
        let (membershipData, memberships) = try await fetchMembershipBindRows(
            householdId: householdId,
            targetProfileId: targetProfileId
        )
        let membershipRaw = String(data: membershipData, encoding: .utf8) ?? "<non-utf8>"
        TrackedDevicePairingLogger.event(
            "admin_snapshot_membership_raw",
            detail: "bytes=\(membershipData.count) body=\(membershipRaw)"
        )
        let membership = memberships.first(where: { $0.isTrackedDevice }) ?? memberships.first
        TrackedDevicePairingLogger.event(
            "admin_snapshot_membership_value",
            detail: "count=\(memberships.count) id=\(membership?.id.uuidString ?? "nil") tracked=\(membership.map { String($0.isTrackedDevice) } ?? "nil") model=\(membership?.trackedDeviceModel ?? "nil") bound=\(membership?.boundAt?.description ?? "nil") nick=\(membership?.nickname ?? "nil")"
        )
        let isBound = membership?.isTrackedDevice == true
        var snapshot = TrackedDeviceAdminBindingSnapshot(
            isBound: isBound,
            nickname: membership?.nickname,
            deviceModel: membership?.trackedDeviceModel,
            boundAt: membership?.boundAt,
            lastReportedAt: nil,
            batteryLevel: nil,
            isCharging: nil,
            addressName: nil
        )
        guard isBound else {
            TrackedDevicePairingLogger.event("admin_snapshot_unbound_return", detail: "no_tracked_membership_row")
            return snapshot
        }

        let locationResponse = try await provider.client
            .from("location_states")
            .select("updated_at,locations")
            .eq("household_id", value: householdId.uuidString.lowercased())
            .eq("entity_id", value: targetProfileId.uuidString.lowercased())
            .limit(1)
            .execute()
        let locationRaw = String(data: locationResponse.data, encoding: .utf8) ?? "<non-utf8>"
        TrackedDevicePairingLogger.event("admin_snapshot_location_raw", detail: locationRaw)

        let locations = (try? SupabaseCodec.makeLiteralColumnDecoder()
            .decode([TrackedDeviceLocationSlice].self, from: locationResponse.data)) ?? []
        let location = locations.first
        let latest = location?.locations?.first
        snapshot.lastReportedAt = latest?.recordedAt ?? location?.updatedAt
        snapshot.batteryLevel = latest?.clampedBatteryLevel
        snapshot.isCharging = latest?.isCharging
        snapshot.addressName = latest?.addressName
        TrackedDevicePairingLogger.event(
            "admin_snapshot_bound_return",
            detail: "model=\(snapshot.deviceModel ?? "nil") bound=\(snapshot.boundAt?.description ?? "nil") report=\(snapshot.lastReportedAt?.description ?? "nil")"
        )
        return snapshot
        #else
        _ = householdId
        _ = targetProfileId
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    private func fetchMembershipBindRows(
        householdId: UUID,
        targetProfileId: UUID
    ) async throws -> (Data, [TrackedDeviceMembershipBindRow]) {
        #if canImport(Supabase)
        let selects = [
            "id,nickname,is_tracked_device,status,profile_id,user_id,joined_at,updated_at,tracked_device_model,tracked_device_bound_at",
            "id,nickname,is_tracked_device,status,profile_id,user_id,joined_at,updated_at",
        ]
        var lastError: Error?
        for select in selects {
            do {
                let response = try await provider.client
                    .from("household_memberships")
                    .select(select)
                    .eq("household_id", value: householdId.uuidString.lowercased())
                    .eq("profile_id", value: targetProfileId.uuidString.lowercased())
                    .execute()
                let rows = try SupabaseCodec.makeLiteralColumnDecoder()
                    .decode([TrackedDeviceMembershipBindRow].self, from: response.data)
                return (response.data, rows)
            } catch {
                lastError = error
                TrackedDevicePairingLogger.failure(error, stage: "admin_snapshot_membership_select")
            }
        }
        throw lastError ?? TrackedDevicePairingError.backendMigrationRequired
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    func reportOwnDeviceModel(_ model: String) async throws {
        #if canImport(Supabase)
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        do {
            _ = try await provider.client
                .rpc(
                    "report_own_tracked_device_model",
                    params: ReportOwnTrackedDeviceModelParams(pModel: trimmed)
                )
                .execute()
        } catch {
            TrackedDevicePairingLogger.failure(error, stage: "report_own_device_model")
        }
        #else
        _ = model
        #endif
    }

    func reportOwnPIN(_ pin: String) async throws {
        #if canImport(Supabase)
        let normalizedPIN = TrackedDevicePINStore.normalize(pin)
        guard TrackedDevicePINStore.isAcceptableInput(normalizedPIN) else {
            throw TrackedDevicePairingError.invalidPIN
        }
        do {
            _ = try await provider.client
                .rpc(
                    "report_own_tracked_device_pin",
                    params: ReportOwnTrackedDevicePINParams(pPin: normalizedPIN)
                )
                .execute()
        } catch {
            throw TrackedDevicePairingSupport.mapClaimError(error)
        }
        #else
        throw TrackedDevicePairingError.sdkUnavailable
        #endif
    }

    private static func decodeOptionalPIN(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(String.self, from: data) {
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t"))
        guard let raw, raw.isEmpty == false, raw.lowercased() != "null" else {
            return nil
        }
        return raw
    }
}

private struct TrackedDevicePairingNonceConsumedRow: Decodable, Sendable {
    let consumedAt: String?

    enum CodingKeys: String, CodingKey {
        case consumedAt = "consumed_at"
    }

    var isConsumed: Bool {
        guard let consumedAt else { return false }
        let trimmed = consumedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty == false && trimmed.lowercased() != "null"
    }
}

private struct TrackedDeviceMembershipBindRow: Decodable, Sendable {
    let id: UUID
    let nickname: String?
    let isTrackedDevice: Bool
    let trackedDeviceModel: String?
    let joinedAt: Date?
    let updatedAt: Date?
    let trackedDeviceBoundAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case isTrackedDevice = "is_tracked_device"
        case trackedDeviceModel = "tracked_device_model"
        case joinedAt = "joined_at"
        case updatedAt = "updated_at"
        case trackedDeviceBoundAt = "tracked_device_bound_at"
    }

    var boundAt: Date? {
        trackedDeviceBoundAt ?? joinedAt ?? updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname)
        isTrackedDevice = try container.decodeIfPresent(Bool.self, forKey: .isTrackedDevice) ?? false
        trackedDeviceModel = try container.decodeIfPresent(String.self, forKey: .trackedDeviceModel)
        joinedAt = Self.decodeDate(container, key: .joinedAt)
        updatedAt = Self.decodeDate(container, key: .updatedAt)
        trackedDeviceBoundAt = Self.decodeDate(container, key: .trackedDeviceBoundAt)
    }

    private static func decodeDate(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) -> Date? {
        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }
        guard let raw = try? container.decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return TrackedDeviceLocationSlice.parseDate(raw)
    }
}

private struct TrackedDeviceLocationSlice: Decodable, Sendable {
    let updatedAt: Date?
    let locations: [LocationPayload]?

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
        case locations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        locations = try container.decodeIfPresent([LocationPayload].self, forKey: .locations)
        if let date = try? container.decodeIfPresent(Date.self, forKey: .updatedAt) {
            updatedAt = date
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .updatedAt) {
            updatedAt = Self.parseDate(raw)
        } else {
            updatedAt = nil
        }
    }

    fileprivate static func parseDate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

struct MockTrackedDevicePairingService: TrackedDevicePairingService {
    func createPairingNonce(
        householdId: UUID,
        managerMembershipId: UUID,
        targetProfileId: UUID
    ) async throws -> String {
        _ = householdId
        _ = managerMembershipId
        _ = targetProfileId
        return "TRACK1"
    }

    func claimPairingNonce(_ code: String) async throws -> UUID {
        _ = code
        return UUID()
    }

    func fetchPIN(householdId: UUID, targetProfileId: UUID) async throws -> String? {
        _ = householdId
        _ = targetProfileId
        return nil
    }

    func setPIN(householdId: UUID, targetProfileId: UUID, pin: String) async throws {
        _ = householdId
        _ = targetProfileId
        _ = pin
    }

    func syncOwnPIN() async throws -> String? {
        nil
    }

    func reportOwnPIN(_ pin: String) async throws {
        _ = pin
    }

    func reportOwnDeviceModel(_ model: String) async throws {
        _ = model
    }

    func isPairingNonceConsumed(_ code: String) async throws -> Bool {
        _ = code
        return false
    }

    func fetchAdminBindingSnapshot(
        householdId: UUID,
        targetProfileId: UUID
    ) async throws -> TrackedDeviceAdminBindingSnapshot {
        _ = householdId
        _ = targetProfileId
        return .unbound
    }
}
