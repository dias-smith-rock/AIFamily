import SwiftUI

struct ProfileDetailView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    let profile: FamilyProfile
    let subtitle: String
    let canEdit: Bool
    let onEdit: () -> Void

    @State private var showIdCard = false
    @State private var showPassport = false
    @State private var showPermit = false

    var body: some View {
        NavigationStack {
            List {
                Section(AppLocalized.string("成员信息", locale: locale)) {
                    LabeledContent(AppLocalized.string("称呼", locale: locale), value: profile.displayName)
                    LabeledContent(AppLocalized.string("角色", locale: locale), value: subtitle)
                    if let gender = profile.gender, gender.isEmpty == false {
                        LabeledContent(AppLocalized.string("性别", locale: locale), value: genderDisplay(gender))
                    }
                    if let birthDate = profile.birthDate, birthDate.isEmpty == false {
                        LabeledContent(AppLocalized.string("生日", locale: locale), value: birthDate)
                    }
                }

                Section(AppLocalized.string("联系方式", locale: locale)) {
                    optionalRow(AppLocalized.string("邮箱", locale: locale), profile.email)
                    optionalRow(AppLocalized.string("手机号", locale: locale), profile.mainPhone)
                    optionalRow(AppLocalized.string("备用手机号", locale: locale), profile.secondPhone)
                }

                Section(AppLocalized.string("证件信息", locale: locale)) {
                    sensitiveRow(
                        title: AppLocalized.string("身份证", locale: locale),
                        value: profile.idCardNum,
                        reveals: $showIdCard
                    )
                    sensitiveRow(
                        title: AppLocalized.string("护照号", locale: locale),
                        value: profile.passportNum,
                        reveals: $showPassport
                    )
                    sensitiveRow(
                        title: AppLocalized.string("旅行证/回乡证号", locale: locale),
                        value: profile.permitNum,
                        reveals: $showPermit
                    )
                }

                Section(AppLocalized.string("补充资料", locale: locale)) {
                    optionalRow(AppLocalized.string("身高", locale: locale), profile.height.map { "\($0) cm" })
                    optionalRow(AppLocalized.string("体重", locale: locale), profile.weight.map { "\($0) kg" })
                    optionalRow(AppLocalized.string("学校", locale: locale), profile.school)
                    optionalRow(AppLocalized.string("年级", locale: locale), profile.grade)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(AppLocalized.string("成员详情", locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(AppLocalized.string("关闭", locale: locale)) { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(AppLocalized.string("编辑", locale: locale)) {
                            onEdit()
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func optionalRow(_ title: String, _ value: String?) -> some View {
        let stableValue = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        LabeledContent(title, value: stableValue.isEmpty ? AppLocalized.string("未填写", locale: locale) : stableValue)
    }

    @ViewBuilder
    private func sensitiveRow(title: String, value: String?, reveals: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(displaySensitive(value, reveals: reveals.wrappedValue))
                .foregroundStyle(.secondary)
            if value?.isEmpty == false {
                Button {
                    reveals.wrappedValue.toggle()
                } label: {
                    Image(systemName: reveals.wrappedValue ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func displaySensitive(_ value: String?, reveals: Bool) -> String {
        let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard text.isEmpty == false else { return AppLocalized.string("未填写", locale: locale) }
        if reveals { return text }
        return maskSensitive(text)
    }

    private func maskSensitive(_ source: String) -> String {
        guard source.count > 8 else { return String(repeating: "*", count: source.count) }
        let prefix = source.prefix(3)
        let suffix = source.suffix(4)
        let stars = String(repeating: "*", count: max(0, source.count - 7))
        return "\(prefix)\(stars)\(suffix)"
    }

    private func genderDisplay(_ value: String) -> String {
        switch value.lowercased() {
        case "male": return AppLocalized.string("男", locale: locale)
        case "female": return AppLocalized.string("女", locale: locale)
        default: return AppLocalized.string("未设置", locale: locale)
        }
    }
}

