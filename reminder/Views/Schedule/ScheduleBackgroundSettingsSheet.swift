import PhotosUI
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// 日程页个人背景设置：纯色 / 图片 / 恢复默认。
struct ScheduleBackgroundSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @EnvironmentObject private var appSettings: AppSettingsManager

    @State private var customPickerColor: Color = .black
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isImportingPhoto = false
    @State private var showRemovePhotoConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    previewCard
                    solidColorSection
                    photoSection
                    resetSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.Schedule.background.localized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel(L10n.Common.close)
                }
            }
            .onAppear {
                syncCustomPickerFromSettings()
            }
            .onChange(of: photoPickerItem) { _, newItem in
                guard let newItem else { return }
                Task { await importPhoto(newItem) }
            }
            .alert(
                L10n.Schedule.backgroundRemovePhotoConfirmTitle,
                isPresented: $showRemovePhotoConfirm
            ) {
                Button(L10n.Common.cancel, role: .cancel) {}
                Button(L10n.Schedule.backgroundRemovePhoto, role: .destructive) {
                    appSettings.clearScheduleBackgroundImage()
                }
            } message: {
                Text(L10n.Schedule.backgroundRemovePhotoConfirmMessage.localized)
            }
        }
        .environment(\.locale, appSettings.appLocale)
        .environment(\.layoutDirection, appSettings.layoutDirection)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var previewCard: some View {
        ZStack {
            SchedulePageBackgroundFill()
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.2)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(spacing: 6) {
                Text(L10n.Schedule.backgroundPreview.localized)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(previewSubtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(16)
        }
        .frame(height: 120)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .id(appSettings.scheduleBackgroundRevision)
    }

    private var previewSubtitle: String {
        switch appSettings.scheduleBackgroundMode {
        case .systemDefault:
            return AppLocalized.string(L10n.Schedule.backgroundModeDefault, locale: locale)
        case .solidColor:
            return AppLocalized.string(L10n.Schedule.backgroundModeSolidColor, locale: locale)
        case .image:
            return AppLocalized.string(L10n.Schedule.backgroundModeImage, locale: locale)
        }
    }

    private var solidColorSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Schedule.backgroundModeSolidColor.localized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4),
                spacing: 14
            ) {
                ForEach(ScheduleBackgroundColorPreset.allCases) { preset in
                    let isSelected =
                        appSettings.scheduleBackgroundMode == .solidColor
                        && appSettings.scheduleBackgroundColorHex?.uppercased() == preset.rawValue
                    colorSwatch(preset.color, isSelected: isSelected) {
                        appSettings.applyScheduleBackgroundColor(hex: preset.rawValue)
                        customPickerColor = preset.color
                    }
                }
            }

            HStack(spacing: 14) {
                Circle()
                    .fill(customPickerColor)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                    }
                    .overlay {
                        if isCustomColorSelected {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.bold))
                                .foregroundStyle(customCheckmarkColor)
                        }
                    }

                ColorPicker(
                    AppLocalized.string(L10n.Common.custom, locale: locale),
                    selection: $customPickerColor,
                    supportsOpacity: false
                )
                .labelsHidden()

                Text(L10n.Common.custom.localized)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(L10n.Common.finish) {
                    appSettings.applyScheduleBackgroundCustomColor(customPickerColor)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Schedule.backgroundModeImage.localized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(AppTheme.ColorToken.accent)
                            .frame(width: 28)
                        Text(L10n.Common.photoLibrary.localized)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        if isImportingPhoto {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isImportingPhoto)

                if appSettings.scheduleBackgroundMode == .image, ScheduleBackgroundStore.hasSavedImage {
                    Divider().padding(.leading, 54)

                    imageFitPickerRow

                    Divider().padding(.leading, 54)

                    Button {
                        showRemovePhotoConfirm = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "trash")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(width: 28)
                            Text(L10n.Schedule.backgroundRemovePhoto.localized)
                                .foregroundStyle(.red)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var imageFitPickerRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 28)
            Text(L10n.Schedule.backgroundImageFit.localized)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Picker(
                AppLocalized.string(L10n.Schedule.backgroundImageFit, locale: locale),
                selection: imageFitBinding
            ) {
                ForEach(ScheduleBackgroundImageFit.allCases) { fit in
                    Text(fit.titleKey).tag(fit)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var imageFitBinding: Binding<ScheduleBackgroundImageFit> {
        Binding(
            get: { appSettings.scheduleBackgroundImageFit },
            set: { appSettings.scheduleBackgroundImageFit = $0 }
        )
    }

    private var resetSection: some View {
        Button {
            appSettings.resetScheduleBackground()
            syncCustomPickerFromSettings()
        } label: {
            HStack {
                Spacer(minLength: 0)
                Text(L10n.Schedule.backgroundResetDefault.localized)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(appSettings.scheduleBackgroundMode == .systemDefault && appSettings.scheduleBackgroundColorHex == nil)
    }

    // MARK: - Helpers

    private var isCustomColorSelected: Bool {
        guard appSettings.scheduleBackgroundMode == .solidColor,
              let hex = appSettings.scheduleBackgroundColorHex
        else { return false }
        return ScheduleBackgroundColorPreset.allCases.contains { $0.rawValue == hex.uppercased() } == false
    }

    private var customCheckmarkColor: Color {
        #if canImport(UIKit)
        let ui = UIColor(customPickerColor)
        var white: CGFloat = 0
        if ui.getWhite(&white, alpha: nil), white > 0.72 {
            return .black.opacity(0.75)
        }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        if ui.getRed(&red, green: &green, blue: &blue, alpha: nil) {
            let luminance = (0.299 * red) + (0.587 * green) + (0.114 * blue)
            return luminance > 0.72 ? .black.opacity(0.75) : .white
        }
        #endif
        return .white
    }

    private func colorSwatch(_ color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 44, height: 44)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                    }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(swatchCheckmarkColor(for: color))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func swatchCheckmarkColor(for color: Color) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var white: CGFloat = 0
        if ui.getWhite(&white, alpha: nil), white > 0.72 {
            return .black.opacity(0.75)
        }
        #endif
        return .white
    }

    private func syncCustomPickerFromSettings() {
        if let hex = appSettings.scheduleBackgroundColorHex,
           let color = Color.taskCardCustomColor(fromHex: hex) {
            customPickerColor = color
        } else {
            customPickerColor = ScheduleBackgroundColorPreset.charcoal.color
        }
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        await MainActor.run { isImportingPhoto = true }
        defer {
            Task { @MainActor in
                isImportingPhoto = false
                photoPickerItem = nil
            }
        }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        await MainActor.run {
            _ = appSettings.applyScheduleBackgroundImageData(data)
        }
    }
}

#Preview {
    ScheduleBackgroundSettingsSheet()
        .environmentObject(AppSettingsManager.shared)
}
