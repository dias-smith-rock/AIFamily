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
                Section(L10n.Family.memberInfo) {
                    ProfileDetailRowView(title: L10n.Common.name, value: profile.displayName)
                    LabeledContent {
                        Text(roleLabel)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text(L10n.Common.role.localized)
                    }
                    if let gender = profile.gender, gender.isEmpty == false {
                        LabeledContent {
                            Text(ProfileDraftGender(databaseValue: gender).localizedName)
                                .foregroundStyle(.secondary)
                        } label: {
                            Text(L10n.Common.gender.localized)
                        }
                    }
                    if let birthDate = profile.birthDate, birthDate.isEmpty == false {
                        ProfileDetailRowView(title: L10n.Common.birthday, value: birthDate)
                    }
                }

                Section(L10n.Common.contactInformation) {
                    ProfileDetailRowView(title: L10n.Common.mail, value: profile.email)
                    ProfileDetailRowView(title: L10n.Common.phoneNumber, value: profile.mainPhone)
                    ProfileDetailRowView(title: L10n.Common.alternatePhone, value: profile.secondPhone)
                }

                Section(L10n.Common.idInformation) {
                    ProfileDetailSensitiveRowView(
                        title: L10n.Common.idCard,
                        value: profile.idCardNum,
                        reveals: $showIdCard
                    )
                    ProfileDetailSensitiveRowView(
                        title: L10n.Common.passportNo,
                        value: profile.passportNum,
                        reveals: $showPassport
                    )
                    ProfileDetailSensitiveRowView(
                        title: L10n.Common.travelPermitHomeReturnPermit,
                        value: profile.permitNum,
                        reveals: $showPermit
                    )
                }

                Section(L10n.Common.additionalInfo) {
                    ProfileDetailRowView(title: L10n.Common.height, value: profile.height.map { "\($0) cm" })
                    ProfileDetailRowView(title: L10n.Common.weight, value: profile.weight.map { "\($0) kg" })
                    ProfileDetailRowView(title: L10n.Common.school, value: profile.school)
                    ProfileDetailRowView(title: L10n.Common.grade, value: profile.grade)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L10n.Family.memberDetails.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.close) { dismiss() }
                }
                if canEdit {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.Common.edit) {
                            onEdit()
                        }
                    }
                }
            }
        }
    }
}
