import SwiftUI

/// 创建/编辑表单中由底部 chip 渐进插入的可选区块（附件为默认行，不在 chip 中）。
enum CreateTaskOptionalSection: String, CaseIterable, Identifiable, Hashable {
    case repeatRule
    case location
    case note
    /// 仅用于编辑 Sheet 复用，不出现在 chip 托盘。
    case files
    case assignee
    case forWhom
    case priority
    case expenses
    case emergency

    var id: String { rawValue }

    /// 底部 chip 可选项（不含默认展示的附件；Expenses 在紧急联系人之前）。
    static var chipCases: [CreateTaskOptionalSection] {
        [
            .repeatRule,
            .location,
            .note,
            .assignee,
            .forWhom,
            .priority,
            .expenses,
            .emergency
        ]
    }

    /// 主卡片中已插入可选行的展示顺序（与 chip 一致）。
    static var summaryCases: [CreateTaskOptionalSection] {
        chipCases
    }

    var systemImage: String {
        switch self {
        case .repeatRule: return "repeat"
        case .location: return "mappin.and.ellipse"
        case .note: return "note.text"
        case .files: return "paperclip"
        case .assignee: return "person.fill"
        case .forWhom: return "person.3"
        case .priority: return "flag"
        case .emergency: return "phone"
        case .expenses: return "banknote"
        }
    }

    var titleKey: L10n.Entry {
        switch self {
        case .repeatRule: return L10n.Common.repeatLabel
        case .location: return L10n.Location.location
        case .note: return L10n.Common.moreDetails
        case .files: return L10n.Common.attachments
        case .assignee: return L10n.Common.assignee
        case .forWhom: return L10n.Common.forWhomFor
        case .priority: return L10n.Schedule.taskPriority2
        case .emergency: return L10n.Common.emergencyContactNumberMeetingLink
        case .expenses: return L10n.Common.expenses
        }
    }

    func title(locale: Locale) -> String {
        AppLocalized.string(titleKey, locale: locale)
    }
}

/// 扁平行：左侧图标 + 标题，右侧自定义内容（紧凑字号）。
struct CreateTaskFlatRow<Trailing: View>: View {
    let systemImage: String
    let title: String
    var iconColor: Color = .accentColor
    var showsChevron: Bool = false
    /// 与创建/详情共用；略紧以匹配表单视觉密度。
    var verticalPadding: CGFloat = CreateTaskFlatRowMetrics.verticalPadding
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(iconColor)
                .frame(width: 18, alignment: .center)

            Text(title)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            trailing()
                .font(.footnote)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, verticalPadding)
        .contentShape(Rectangle())
    }
}

enum CreateTaskFlatRowMetrics {
    static let verticalPadding: CGFloat = 8
    static let dividerLeadingInset: CGFloat = 40
}

/// 创建/详情扁平行之间的分隔线（高度固定，避免系统 Divider 额外占位不一致）。
struct CreateTaskFlatDivider: View {
    var leadingInset: CGFloat = CreateTaskFlatRowMetrics.dividerLeadingInset

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.1))
            .frame(height: 0.5)
            .frame(maxWidth: .infinity)
            .padding(.leading, leadingInset)
    }
}

/// 将 Toggle / compact DatePicker 缩放到与 footnote 标签接近的视觉高度。
enum CreateTaskFormControlMetrics {
    static let scale: CGFloat = 0.78
    /// scaleEffect 不改变布局占位，用负 padding 收回多余空白。
    static var verticalLayoutCompensation: CGFloat { -(1 - scale) * 14 }
}

extension View {
    func createTaskFormCompactControl(anchor: UnitPoint = .trailing) -> some View {
        controlSize(.mini)
            .scaleEffect(CreateTaskFormControlMetrics.scale, anchor: anchor)
            .padding(.vertical, CreateTaskFormControlMetrics.verticalLayoutCompensation)
    }
}

/// 自定义日期/时间选择：行内 footnote 胶囊 + Sheet 内缩小字号，与主表单一致。
/// `dateAndTime` 模式下日期胶囊与时间胶囊分别打开对应 Sheet，互不混排。
struct CreateTaskFormDateTimePicker: View {
    enum Mode: Hashable, Identifiable {
        case date
        case time
        case dateAndTime

        var id: String {
            switch self {
            case .date: return "date"
            case .time: return "time"
            case .dateAndTime: return "dateAndTime"
            }
        }
    }

    @Binding var selection: Date
    let mode: Mode
    var locale: Locale = .current
    var accent: Color = .accentColor

    /// 当前弹出的选择器类型（日期或时间）。
    @State private var presentedPicker: Mode?

    var body: some View {
        Group {
            switch mode {
            case .date:
                Button {
                    presentedPicker = .date
                } label: {
                    capsuleLabel(dateText)
                }
                .buttonStyle(.plain)
            case .time:
                Button {
                    presentedPicker = .time
                } label: {
                    capsuleLabel(timeText)
                }
                .buttonStyle(.plain)
            case .dateAndTime:
                HStack(spacing: 4) {
                    Button {
                        presentedPicker = .date
                    } label: {
                        capsuleLabel(dateText)
                    }
                    .buttonStyle(.plain)

                    Button {
                        presentedPicker = .time
                    } label: {
                        capsuleLabel(timeText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $presentedPicker) { picker in
            pickerSheet(for: picker)
        }
    }

    private func capsuleLabel(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
    }

    private var dateText: String {
        selection.formatted(
            .dateTime
                .year()
                .month(.abbreviated)
                .day()
                .locale(locale)
        )
    }

    private var timeText: String {
        ScheduleTimeFormatting.timelineClockTime(selection, locale: locale)
    }

    private func pickerSheet(for picker: Mode) -> some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    switch picker {
                    case .date:
                        DatePicker("", selection: $selection, displayedComponents: [.date])
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(.horizontal, 4)
                    case .time:
                        DatePicker("", selection: $selection, displayedComponents: [.hourAndMinute])
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .frame(maxHeight: 132)
                            .environment(
                                \.locale,
                                ScheduleTimeFormatting.twentyFourHourLocale(basedOn: locale)
                            )
                    case .dateAndTime:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity)
                .environment(\.dynamicTypeSize, .small)
                .font(.footnote)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        presentedPicker = nil
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .environment(\.locale, locale)
        .tint(accent)
        .presentationDetents(picker == .time ? [.height(280), .medium] : [.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// 底部渐进加字段 chip 托盘（自动换行；卡片样式与主设置组一致）。
struct CreateTaskChipTray: View {
    let sectionTitles: [(CreateTaskOptionalSection, String)]
    let accent: Color
    let onSelect: (CreateTaskOptionalSection) -> Void

    var body: some View {
        LedgerTagCapsuleFlow(spacing: 8) {
            Image(systemName: "plus")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 28, height: 28)

            ForEach(sectionTitles, id: \.0) { section, title in
                Button {
                    onSelect(section)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: section.systemImage)
                            .font(.caption2.weight(.semibold))
                        Text(title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color(.tertiarySystemFill), in: Capsule())
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }
}

/// 任务色预设（写入 `background_color`）。
enum CreateTaskColorPreset: String, CaseIterable, Identifiable {
    case green = "#34C759"
    case blue = "#007AFF"
    case purple = "#AF52DE"
    case orange = "#FF9500"
    case red = "#FF3B30"
    case teal = "#5AC8FA"
    case pink = "#FF2D55"
    case indigo = "#5856D6"

    var id: String { rawValue }

    var color: Color {
        Color.taskCardLeadingAccent(fromHex: rawValue)
    }

    /// VoiceOver / Menu 旁白用短名，不展示 hex。
    var accessibilityTitle: String {
        switch self {
        case .green: return "Green"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .orange: return "Orange"
        case .red: return "Red"
        case .teal: return "Teal"
        case .pink: return "Pink"
        case .indigo: return "Indigo"
        }
    }
}
