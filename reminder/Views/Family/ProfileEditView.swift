import SwiftUI
import PhotosUI
import UIKit
import Kingfisher

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let householdId: UUID?
    let canEdit: Bool
    let memberRemoval: MemberRemovalAction?
    let adminRoleToggle: AdminRoleToggleAction?
    let uploadAvatar: @MainActor (Data, UUID?) async -> URL?
    let onSave: @MainActor (UUID, LocalProfileDraft) async -> String?

    @State private var showDeleteAlert = false
    @State private var showAdminToggleAlert = false
    @State private var isDeleting = false
    @State private var isUpdatingAdminRole = false
    @State private var name: String
    @State private var gender: ProfileDraftGender
    @State private var shouldSetBirthDate: Bool
    @State private var birthDate: Date
    @State private var height = ""
    @State private var weight = ""
    @State private var school = ""
    @State private var grade = ""
    @State private var email = ""
    @State private var mainPhone = ""
    @State private var secondPhone = ""
    @State private var idCardNum = ""
    @State private var passportNum = ""
    @State private var permitNum = ""
    @State private var avatarURL: URL?
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarSelectionNonce = 0
    @State private var isUploadingAvatar = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        mode: Mode,
        householdId: UUID?,
        canEdit: Bool,
        memberRemoval: MemberRemovalAction? = nil,
        adminRoleToggle: AdminRoleToggleAction? = nil,
        uploadAvatar: @escaping @MainActor (Data, UUID?) async -> URL?,
        onSave: @escaping @MainActor (UUID, LocalProfileDraft) async -> String?
    ) {
        self.mode = mode
        self.householdId = householdId
        self.canEdit = canEdit
        self.memberRemoval = memberRemoval
        self.adminRoleToggle = adminRoleToggle
        self.uploadAvatar = uploadAvatar
        self.onSave = onSave

        let profile = mode.profile
        _name = State(initialValue: Self.initialNameFieldValue(for: profile))
        _gender = State(initialValue: ProfileDraftGender(databaseValue: profile?.gender))
        if let rawBirthDate = profile?.birthDate,
           let date = Self.birthDateFormatter.date(from: rawBirthDate) {
            _shouldSetBirthDate = State(initialValue: true)
            _birthDate = State(initialValue: date)
        } else {
            _shouldSetBirthDate = State(initialValue: false)
            _birthDate = State(initialValue: Date())
        }
        _height = State(initialValue: profile?.height.map { "\($0)" } ?? "")
        _weight = State(initialValue: profile?.weight.map { "\($0)" } ?? "")
        _school = State(initialValue: profile?.school ?? "")
        _grade = State(initialValue: profile?.grade ?? "")
        _email = State(initialValue: profile?.email ?? "")
        _mainPhone = State(initialValue: profile?.mainPhone ?? "")
        _secondPhone = State(initialValue: profile?.secondPhone ?? "")
        _idCardNum = State(initialValue: profile?.idCardNum ?? "")
        _passportNum = State(initialValue: profile?.passportNum ?? "")
        _permitNum = State(initialValue: profile?.permitNum ?? "")
        _avatarURL = State(initialValue: profile?.avatarUrl.flatMap(URL.init(string:)))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        avatarView
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.Family.profilePhoto.localized)
                                .font(.headline)
                            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                                Group {
                                    if isUploadingAvatar {
                                        Text(L10n.Common.uploading.localized)
                                    } else {
                                        Text(L10n.Common.choosePhoto.localized)
                                    }
                                }
                                .font(.subheadline.weight(.semibold))
                            }
                            .disabled(canEdit == false || isUploadingAvatar)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(L10n.Common.basicInfo) {
                    TextField(L10n.Common.nicknameSuchAsMum.localized, text: $name)
                    Picker(L10n.Common.gender.localized, selection: $gender) {
                        ForEach(ProfileDraftGender.allCases) { item in
                            Text(item.localizedName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle(L10n.Common.setBirthday.localized, isOn: $shouldSetBirthDate)
                    if shouldSetBirthDate {
                        DatePicker(L10n.Common.birthday.localized, selection: $birthDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                Section(L10n.Common.contactInformation) {
                    TextField(L10n.Common.mail.localized, text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField(L10n.Common.phoneNumber.localized, text: $mainPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                    TextField(L10n.Common.alternatePhone.localized, text: $secondPhone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }

                Section(L10n.Common.growthData) {
                    TextField(L10n.Common.heightCm.localized, text: $height)
                        .keyboardType(.decimalPad)
                    TextField(L10n.Common.weightKg.localized, text: $weight)
                        .keyboardType(.decimalPad)
                }

                Section(L10n.Common.educationAndDocuments) {
                    TextField(L10n.Common.attendSchool.localized, text: $school)
                    TextField(L10n.Common.currentGrade.localized, text: $grade)
                    TextField(L10n.Common.idNumber.localized, text: $idCardNum)
                    TextField(L10n.Common.passportNo.localized, text: $passportNum)
                    TextField(L10n.Common.travelPermitReturnPermitNumber.localized, text: $permitNum)
                }

                if let adminRoleToggle {
                    Section {
                        Button {
                            showAdminToggleAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                if isUpdatingAdminRole {
                                    ProgressView()
                                } else {
                                    Text(adminRoleToggle.buttonTitle)
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isUpdatingAdminRole || isDeleting || isSaving || isUploadingAvatar)
                    }
                }

                if let memberRemoval {
                    Section {
                        Button(role: .destructive) {
                            showDeleteAlert = true
                        } label: {
                            HStack {
                                Spacer()
                                if isDeleting {
                                    ProgressView()
                                } else {
                                    Text(memberRemoval.buttonTitle)
                                        .fontWeight(.bold)
                                }
                                Spacer()
                            }
                        }
                        .disabled(isDeleting || isSaving || isUploadingAvatar || isUpdatingAdminRole)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.navigationTitleKey)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSaving { ProgressView() } else { Text(L10n.Common.save.localized) }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || canEdit == false || isSaving || isUploadingAvatar)
                }
            }
            .onChange(of: avatarPickerItem) { _, newItem in
                guard let newItem else { return }
                avatarSelectionNonce += 1
                uploadSelectedAvatar(newItem, nonce: avatarSelectionNonce)
            }
            .alert(L10n.Common.areYouSureYouWantToContinue, isPresented: $showDeleteAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.ok, role: .destructive) {
                    performMemberRemoval()
                }
            } message: {
                if let memberRemoval {
                    Text(
                        memberRemoval.isVirtualMember
                            ? L10n.Family.thisVirtualMemberProfileCannotBeRecovered.localized
                            : L10n.Schedule.afterRemovalTheyCanNoLongerAccessThisGro.localized
                    )
                }
            }
            .alert(adminToggleAlertTitle, isPresented: $showAdminToggleAlert) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Common.ok) {
                    performAdminRoleToggle()
                }
            } message: {
                Text(adminToggleAlertMessage)
            }
        }
    }

    private var adminToggleAlertTitle: LocalizedStringKey {
        guard let adminRoleToggle else { return L10n.Common.areYouSureYouWantToContinue.localized }
        return adminRoleToggle.isPromoting ? L10n.Family.makeThisMemberAnAdmin.localized : L10n.Family.removeThisMemberSAdminRole.localized
    }

    private var adminToggleAlertMessage: LocalizedStringKey {
        guard let adminRoleToggle else { return "" }
        return adminRoleToggle.isPromoting
            ? L10n.Family.adminsCanHelpManageGroupMembersAndSetting.localized
            : L10n.Family.theyWillReturnToRegularMemberPermissions.localized
    }

    private func performAdminRoleToggle() {
        guard let adminRoleToggle else { return }
        isUpdatingAdminRole = true
        errorMessage = nil
        Task { @MainActor in
            defer { isUpdatingAdminRole = false }
            let failure = await adminRoleToggle.onToggle()
            if let failure {
                errorMessage = failure
            } else {
                dismiss()
            }
        }
    }

    private func performMemberRemoval() {
        guard let memberRemoval else { return }
        isDeleting = true
        errorMessage = nil
        Task { @MainActor in
            defer { isDeleting = false }
            let failure = await memberRemoval.onDelete()
            if let failure {
                errorMessage = failure
            } else {
                dismiss()
            }
        }
    }

    private var avatarView: some View {
        Group {
            if let avatarURL {
                KFImage.url(avatarURL)
                    .placeholder { ProgressView() }
                    .cacheMemoryOnly(false)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackAvatar
            }
        }
        .frame(width: 62, height: 62)
        .clipShape(Circle())
    }

    private var fallbackAvatar: some View {
        let firstChar = name.trimmingCharacters(in: .whitespacesAndNewlines).first.map(String.init) ?? "?"
        return Text(firstChar)
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.opacity(0.9))
    }

    private func uploadSelectedAvatar(_ item: PhotosPickerItem, nonce: Int) {
        guard canEdit else { return }
        errorMessage = nil
        isUploadingAvatar = true
        Task { @MainActor in
            defer {
                isUploadingAvatar = false
            }
            do {
                #if DEBUG
                print("⏳ [FamilyDebug] 开始从相册读取图片...")
                #endif
                guard let rawData = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = AppLocalized.localized(L10n.Common.couldNotReadImageDataPleaseChooseAgain)
                    #if DEBUG
                    print("❌ [FamilyDebug] 读取失败：无法提取原始数据")
                    #endif
                    return
                }
                guard rawData.isEmpty == false else {
                    errorMessage = AppLocalized.localized(L10n.Common.imageDataWasEmptyPleaseChooseAgain)
                    #if DEBUG
                    print("❌ [FamilyDebug] 原始数据为空（0 bytes）")
                    #endif
                    return
                }

                guard let image = UIImage(data: rawData) else {
                    errorMessage = AppLocalized.localized(L10n.Common.unsupportedImageFormatPleaseTryAnotherPhot)
                    #if DEBUG
                    print("❌ [FamilyDebug] 转换失败：原始数据无法渲染为 UIImage")
                    #endif
                    return
                }

                guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
                    errorMessage = AppLocalized.localized(L10n.Common.imageCompressionFailedPleaseTryAgain)
                    #if DEBUG
                    print("❌ [FamilyDebug] 压缩失败：无法生成 JPEG 数据")
                    #endif
                    return
                }

                guard jpegData.isEmpty == false else {
                    errorMessage = AppLocalized.localized(L10n.Common.compressedImageDataWasEmptyPleaseTryAgain)
                    #if DEBUG
                    print("❌ [FamilyDebug] 校验失败：JPEG 数据为 0 字节")
                    #endif
                    return
                }

                #if DEBUG
                print("✅ [FamilyDebug] 成功获取并压缩图片数据，最终大小: \(jpegData.count) 字节")
                #endif
                let snapshot = Data(jpegData)
                #if DEBUG
                print("📦 [FamilyDebug] ProfileEditView upload snapshot bytes=\(snapshot.count), nonce=\(nonce)")
                #endif
                let url = await uploadAvatar(snapshot, mode.profile?.id)
                guard nonce == avatarSelectionNonce else {
                    #if DEBUG
                    print("⚠️ [FamilyDebug] skip stale avatar upload result, nonce=\(nonce), latest=\(avatarSelectionNonce)")
                    #endif
                    return
                }
                if let url {
                    avatarURL = url
                } else {
                    errorMessage = errorMessage ?? AppLocalized.localized(L10n.Common.avatarUploadFailedPleaseTryAgainLater)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard canEdit else {
            errorMessage = AppLocalized.localized(L10n.Common.youDoNotHavePermissionToEditThisProfile)
            return
        }
        guard let householdId else {
            errorMessage = AppLocalized.localized(L10n.Family.noGroupIsCurrentlySelected)
            return
        }

        let draft = LocalProfileDraft(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarURL: avatarURL?.absoluteString,
            gender: gender.dbValue,
            birthDate: shouldSetBirthDate ? birthDate : nil,
            idCardNum: trimmedOrNil(idCardNum),
            passportNum: trimmedOrNil(passportNum),
            permitNum: trimmedOrNil(permitNum),
            height: parseDoubleOrNil(height),
            weight: parseDoubleOrNil(weight),
            school: trimmedOrNil(school),
            grade: trimmedOrNil(grade),
            email: trimmedOrNil(email),
            mainPhone: trimmedOrNil(mainPhone),
            secondPhone: trimmedOrNil(secondPhone)
        )
        guard draft.name.isEmpty == false else {
            errorMessage = AppLocalized.localized(L10n.Common.nameCannotBeEmpty)
            return
        }

        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            let failure = await onSave(householdId, draft)
            isSaving = false
            if let failure {
                errorMessage = failure
            } else {
                dismiss()
            }
        }
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDoubleOrNil(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        return Double(trimmed)
    }

    private static func initialNameFieldValue(for profile: FamilyProfile?) -> String {
        guard let profile else { return "" }
        if let nickname = profile.membershipNickname {
            return nickname
        }
        return profile.name
    }

    private static let birthDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

extension ProfileEditView {
    struct AdminRoleToggleAction {
        let buttonTitle: LocalizedStringKey
        let isPromoting: Bool
        let onToggle: @MainActor () async -> String?
    }

    struct MemberRemovalAction {
        let buttonTitle: LocalizedStringKey
        let isVirtualMember: Bool
        let onDelete: @MainActor () async -> String?
    }

    enum Mode {
        /// 编辑已有档案：`FamilyProfile.id` 即 `family_profiles` 主键，作为双表更新的 `targetProfileId`。
        case createLocalProfile
        case edit(FamilyProfile)

        var profile: FamilyProfile? {
            if case .edit(let profile) = self { return profile }
            return nil
        }

        var navigationTitleKey: LocalizedStringKey {
            switch self {
            case .createLocalProfile: L10n.Family.createMemberProfile.localized
            case .edit: L10n.Common.editProfile.localized
            }
        }
    }
}

enum ProfileDraftGender: String, CaseIterable, Identifiable {
    case unspecified
    case male
    case female

    var id: String { rawValue }

    init(databaseValue: String?) {
        switch databaseValue?.lowercased() {
        case "male": self = .male
        case "female": self = .female
        default: self = .unspecified
        }
    }

    var localizedName: LocalizedStringKey {
        switch self {
        case .unspecified: L10n.Common.notSet.localized
        case .male: L10n.Common.male.localized
        case .female: L10n.Common.female.localized
        }
    }

    var dbValue: String? {
        switch self {
        case .unspecified: return nil
        case .male: return "male"
        case .female: return "female"
        }
    }
}

