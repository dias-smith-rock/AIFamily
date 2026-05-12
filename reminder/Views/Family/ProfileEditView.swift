import SwiftUI
import PhotosUI
import UIKit
import Kingfisher

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let householdId: UUID?
    let canEdit: Bool
    let uploadAvatar: @MainActor (Data, UUID?) async -> URL?
    let onSave: @MainActor (UUID, ManagedProfileDraft) async -> String?

    @State private var name: String
    @State private var gender: ManagedProfileGender
    @State private var shouldSetBirthDate: Bool
    @State private var birthDate: Date
    @State private var height = ""
    @State private var weight = ""
    @State private var school = ""
    @State private var grade = ""
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
        uploadAvatar: @escaping @MainActor (Data, UUID?) async -> URL?,
        onSave: @escaping @MainActor (UUID, ManagedProfileDraft) async -> String?
    ) {
        self.mode = mode
        self.householdId = householdId
        self.canEdit = canEdit
        self.uploadAvatar = uploadAvatar
        self.onSave = onSave

        let profile = mode.profile
        _name = State(initialValue: profile?.name ?? "")
        _gender = State(initialValue: ManagedProfileGender(databaseValue: profile?.gender))
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
                            Text("成员头像")
                                .font(.headline)
                            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                                Text(isUploadingAvatar ? "上传中..." : "选择头像")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .disabled(canEdit == false || isUploadingAvatar)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("基础信息") {
                    TextField("称呼 (如：大宝、旺财) *", text: $name)
                    Picker("性别", selection: $gender) {
                        ForEach(ManagedProfileGender.allCases) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("设置生日", isOn: $shouldSetBirthDate)
                    if shouldSetBirthDate {
                        DatePicker("生日", selection: $birthDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                Section("成长数据") {
                    TextField("身高 (cm)", text: $height)
                        .keyboardType(.decimalPad)
                    TextField("体重 (kg)", text: $weight)
                        .keyboardType(.decimalPad)
                }

                Section("教育与证件") {
                    TextField("就读学校", text: $school)
                    TextField("当前年级", text: $grade)
                    TextField("身份证件号码", text: $idCardNum)
                    TextField("护照号", text: $passportNum)
                    TextField("旅行证 / 回乡证号", text: $permitNum)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        submit()
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || canEdit == false || isSaving || isUploadingAvatar)
                }
            }
            .onChange(of: avatarPickerItem) { _, newItem in
                guard let newItem else { return }
                avatarSelectionNonce += 1
                uploadSelectedAvatar(newItem, nonce: avatarSelectionNonce)
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
                    errorMessage = "未能读取图片数据，请重新选择。"
                    #if DEBUG
                    print("❌ [FamilyDebug] 读取失败：无法提取原始数据")
                    #endif
                    return
                }
                guard rawData.isEmpty == false else {
                    errorMessage = "读取到原始图片数据为空，请重新选择。"
                    #if DEBUG
                    print("❌ [FamilyDebug] 原始数据为空（0 bytes）")
                    #endif
                    return
                }

                guard let image = UIImage(data: rawData) else {
                    errorMessage = "图片格式解析失败，请换一张图片重试。"
                    #if DEBUG
                    print("❌ [FamilyDebug] 转换失败：原始数据无法渲染为 UIImage")
                    #endif
                    return
                }

                guard let jpegData = image.jpegData(compressionQuality: 0.7) else {
                    errorMessage = "图片压缩失败，请重试。"
                    #if DEBUG
                    print("❌ [FamilyDebug] 压缩失败：无法生成 JPEG 数据")
                    #endif
                    return
                }

                guard jpegData.isEmpty == false else {
                    errorMessage = "压缩后图片数据为空，请重试。"
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
                    errorMessage = errorMessage ?? "头像上传失败，请稍后再试。"
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func submit() {
        guard canEdit else {
            errorMessage = "当前没有权限编辑该资料。"
            return
        }
        guard let householdId else {
            errorMessage = "当前未选择家庭。"
            return
        }

        let draft = ManagedProfileDraft(
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
            grade: trimmedOrNil(grade)
        )
        guard draft.name.isEmpty == false else {
            errorMessage = "称呼不能为空。"
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
    enum Mode {
        case createManaged
        case edit(FamilyProfile)

        var profile: FamilyProfile? {
            if case .edit(let profile) = self { return profile }
            return nil
        }

        var navigationTitle: String {
            switch self {
            case .createManaged: return "添加托管角色"
            case .edit: return "编辑资料"
            }
        }
    }
}

private enum ManagedProfileGender: String, CaseIterable, Identifiable {
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

    var displayName: String {
        switch self {
        case .unspecified: return "未设置"
        case .male: return "男"
        case .female: return "女"
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

