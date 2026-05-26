import Foundation

#if canImport(Supabase)
import Supabase

/// 构建 `family_profiles` 更新请求体：空选填字段显式发送 `null`，避免 Encodable 省略 `nil` 导致库内旧值残留。
enum FamilyProfileUpdatePayload {
    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func build(from draft: LocalProfileDraft) -> [String: AnyJSON] {
        let draft = draft.normalizedForProfileUpdate()
        var updatePayload: [String: AnyJSON] = [:]

        updatePayload["name"] = .string(draft.name)
        updatePayload["avatar_url"] = jsonStringOrNull(draft.avatarURL)
        updatePayload["gender"] = jsonStringOrNull(draft.gender)
        updatePayload["birth_date"] = jsonBirthDateOrNull(draft.birthDate)
        updatePayload["id_card_num"] = jsonStringOrNull(draft.idCardNum)
        updatePayload["passport_num"] = jsonStringOrNull(draft.passportNum)
        updatePayload["permit_num"] = jsonStringOrNull(draft.permitNum)
        updatePayload["height"] = jsonDoubleOrNull(draft.height)
        updatePayload["weight"] = jsonDoubleOrNull(draft.weight)
        updatePayload["school"] = jsonStringOrNull(draft.school)
        updatePayload["grade"] = jsonStringOrNull(draft.grade)
        updatePayload["email"] = jsonStringOrNull(draft.email)
        updatePayload["mainphone"] = jsonStringOrNull(draft.mainPhone)
        updatePayload["secondphone"] = jsonStringOrNull(draft.secondPhone)

        return updatePayload
    }

    private static func jsonStringOrNull(_ value: String?) -> AnyJSON {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? .null : .string(trimmed)
    }

    private static func jsonBirthDateOrNull(_ value: Date?) -> AnyJSON {
        guard let value else { return .null }
        return .string(birthDateFormatter.string(from: value))
    }

    private static func jsonDoubleOrNull(_ value: Double?) -> AnyJSON {
        guard let value else { return .null }
        return .double(value)
    }
}
#endif
