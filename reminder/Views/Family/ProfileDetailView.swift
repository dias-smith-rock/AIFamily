import SwiftUI

struct ProfileDetailView: View {
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
                Section("成员信息") {
                    LabeledContent("称呼", value: profile.name)
                    LabeledContent("角色", value: subtitle)
                    if let gender = profile.gender, gender.isEmpty == false {
                        LabeledContent("性别", value: genderDisplay(gender))
                    }
                    if let birthDate = profile.birthDate, birthDate.isEmpty == false {
                        LabeledContent("生日", value: birthDate)
                    }
                }

                Section("证件信息") {
                    sensitiveRow(
                        title: "身份证",
                        value: profile.idCardNum,
                        reveals: $showIdCard
                    )
                    sensitiveRow(
                        title: "护照号",
                        value: profile.passportNum,
                        reveals: $showPassport
                    )
                    sensitiveRow(
                        title: "旅行证/回乡证号",
                        value: profile.permitNum,
                        reveals: $showPermit
                    )
                }

                Section("补充资料") {
                    optionalRow("身高", profile.height.map { "\($0) cm" })
                    optionalRow("体重", profile.weight.map { "\($0) kg" })
                    optionalRow("学校", profile.school)
                    optionalRow("年级", profile.grade)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("成员详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("编辑") {
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
        LabeledContent(title, value: stableValue.isEmpty ? "未填写" : stableValue)
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
        guard text.isEmpty == false else { return "未填写" }
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
        case "male": return "男"
        case "female": return "女"
        default: return "未设置"
        }
    }
}

