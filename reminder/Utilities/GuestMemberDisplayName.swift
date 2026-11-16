import Foundation

#if canImport(Supabase)
import Supabase
#endif

/// 游客（匿名 Auth）加入群组时的默认可区分展示名：八位数字。已写入的六位编号保持原样。
enum GuestMemberDisplayName {
    /// 库内已经写好的游客编号：六位（历史）或八位（新分配）。
    static func isPersistedGuestNumericIdentifier(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: "^[0-9]{6}$|^[0-9]{8}$", options: .regularExpression) != nil
    }

    static func isSixDigitIdentifier(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: "^[0-9]{6}$", options: .regularExpression) != nil
    }

    /// 新随机八位数字（00000000–99999999）。
    static func generateRandomEightDigit() -> String {
        String(format: "%08d", Int.random(in: 0 ... 99_999_999))
    }

    /// 由 `family_profiles.id` 推导的稳定八位标签（占位名还没写入库时，各设备看到同一个数）。
    static func stableEightDigitLabel(profileId: UUID) -> String {
        let uuid = profileId.uuid
        var value: UInt64 = 0
        withUnsafeBytes(of: uuid) { raw in
            for byte in raw.prefix(8) {
                value = value &* 131 &+ UInt64(byte)
            }
        }
        return String(format: "%08d", value % 100_000_000)
    }

    /// 占位名（「新成员」等）在 UI 中应展示的字符串。
    static func resolvedDisplayName(stored: String, profileId: UUID) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || FamilyProfile.isNewMemberPlaceholder(trimmed) {
            return stableEightDigitLabel(profileId: profileId)
        }
        if isPersistedGuestNumericIdentifier(trimmed) {
            return trimmed
        }
        return trimmed
    }
}

#if canImport(Supabase)
/// 游客成功 `join_household` 后，将 membership / profile 的占位名写入随机八位数字。
enum GuestMemberDisplayNameAssigner {
    private struct MembershipRow: Decodable {
        let id: UUID
        let householdId: UUID
        let profileId: UUID?
        let nickname: String?

        enum CodingKeys: String, CodingKey {
            case id
            case householdId = "household_id"
            case profileId = "profile_id"
            case nickname
        }
    }

    private struct ProfileNameRow: Decodable {
        let name: String?
    }

    @MainActor
    static func assignAfterJoinIfNeeded() async {
        guard await SupabaseAuthManager.isAnonymousUser() else { return }
        guard let userId = await SupabaseAuthManager.currentUserId() else { return }

        let client = SupabaseManager.shared.client
        do {
            let memberships: [MembershipRow] = try await client
                .from("household_memberships")
                .select("id,household_id,profile_id,nickname")
                .eq("user_id", value: userId.uuidString.lowercased())
                .order("created_at", ascending: false)
                .limit(1)
                .execute()
                .value

            guard let membership = memberships.first else { return }

            let nicknameTrimmed = membership.nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if GuestMemberDisplayName.isPersistedGuestNumericIdentifier(nicknameTrimmed) {
                return
            }

            let nicknameIsPlaceholder = nicknameTrimmed.isEmpty
                || FamilyProfile.isNewMemberPlaceholder(nicknameTrimmed)

            var profileNameIsPlaceholder = true
            var profileNameTrimmed = ""
            if let profileId = membership.profileId {
                let profiles: [ProfileNameRow] = try await client
                    .from("family_profiles")
                    .select("name")
                    .eq("id", value: profileId.uuidString.lowercased())
                    .limit(1)
                    .execute()
                    .value
                profileNameTrimmed = profiles.first?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if GuestMemberDisplayName.isPersistedGuestNumericIdentifier(profileNameTrimmed) {
                    return
                }
                profileNameIsPlaceholder = profileNameTrimmed.isEmpty
                    || FamilyProfile.isNewMemberPlaceholder(profileNameTrimmed)
            }

            guard nicknameIsPlaceholder || profileNameIsPlaceholder else { return }

            let displayName = GuestMemberDisplayName.generateRandomEightDigit()

            try await client
                .from("household_memberships")
                .update(["nickname": displayName])
                .eq("id", value: membership.id.uuidString.lowercased())
                .execute()

            if let profileId = membership.profileId {
                try await client
                    .from("family_profiles")
                    .update(["name": displayName])
                    .eq("id", value: profileId.uuidString.lowercased())
                    .execute()
            }

            #if DEBUG
            print(
                "[GuestMemberDisplayName] assigned guest label=\(displayName) membership=\(membership.id.uuidString.lowercased())"
            )
            #endif
        } catch {
            #if DEBUG
            print("[GuestMemberDisplayName] assignAfterJoinIfNeeded failed: \(error.localizedDescription)")
            #endif
        }
    }
}
#endif
