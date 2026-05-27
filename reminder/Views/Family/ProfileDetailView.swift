import SwiftUI

struct ProfileDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let profile: FamilyProfile
    let roleLabel: LocalizedStringKey
    let canEdit: Bool
    let onEdit: () -> Void

    @State private var showIdCard = false
    @State private var showPassport = false
    @State private var showPermit = false

    var body: some View {
        NavigationStack {
            List {
                Section("成员信息") {
                    ProfileDetailRowView(title: "称呼", value: profile.displayName)
                    LabeledContent {
                        Text(roleLabel)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("角色")
                    }
                    if let gender = profile.gender, gender.isEmpty == false {
                        LabeledContent {
                            Text(ProfileDraftGender(databaseValue: gender).localizedName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text("性别")
                        }
                    }
                    if let birthDate = profile.birthDate, birthDate.isEmpty == false {
                        ProfileDetailRowView(title: "生日", value: birthDate)
                    }
                }

                Section("联系方式") {
                    ProfileDetailRowView(title: "邮箱", value: profile.email)
                    ProfileDetailRowView(title: "手机号", value: profile.mainPhone)
                    ProfileDetailRowView(title: "备用手机号", value: profile.secondPhone)
                }

                Section("证件信息") {
                    ProfileDetailSensitiveRowView(
                        title: "身份证",
                        value: profile.idCardNum,
                        reveals: $showIdCard
                    )
                    ProfileDetailSensitiveRowView(
                        title: "护照号",
                        value: profile.passportNum,
                        reveals: $showPassport
                    )
                    ProfileDetailSensitiveRowView(
                        title: "旅行证/回乡证号",
                        value: profile.permitNum,
                        reveals: $showPermit
                    )
                }

                Section("补充资料") {
                    ProfileDetailRowView(title: "身高", value: profile.height.map { "\($0) cm" })
                    ProfileDetailRowView(title: "体重", value: profile.weight.map { "\($0) kg" })
                    ProfileDetailRowView(title: "学校", value: profile.school)
                    ProfileDetailRowView(title: "年级", value: profile.grade)
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
}
