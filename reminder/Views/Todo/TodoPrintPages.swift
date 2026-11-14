import SwiftUI
import UIKit

struct TodoPrintTask: Identifiable {
    let id: UUID
    let task: FamilyTask
    let title: String
    let deadline: String?
    let details: [String]
    let avatars: [TaskCardAvatarSource]
    let hasAttachments: Bool
    let backgroundHex: String?
    let theme: Color
}

struct TodoPrintSection: Identifiable {
    let id = UUID()
    let title: String
    let tasks: [TodoPrintTask]
}

struct PlannerPrintRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
}

@MainActor
enum TodoPrintComposer {
    static func printList(
        jobName: String,
        householdName: String,
        sections: [TodoPrintSection],
        locale: Locale
    ) {
        let pieces = listPieces(sections)
        let pages = paginate(pieces, locale: locale, sticksToNext: { piece in
            if case .header = piece { return true }
            return false
        }, measure: { piece in
            TodoListPrintMeasure(piece: piece)
        }, measuredPage: { slice in
            TodoListPrintPage(householdName: householdName, pieces: slice, fillsPage: false)
        }, page: { slice in
            TodoListPrintPage(householdName: householdName, pieces: slice, fillsPage: true)
        })
        present(jobName: jobName, pages: pages, locale: locale)
    }

    static func printSticky(
        jobName: String,
        householdName: String,
        notes: [TodoPrintTask],
        locale: Locale
    ) {
        let grid = StickyPrintGrid.make()
        let chunks: [[TodoPrintTask]]
        if notes.isEmpty {
            chunks = [[]]
        } else {
            chunks = stride(from: 0, to: notes.count, by: grid.perPage).map { start in
                Array(notes[start..<min(start + grid.perPage, notes.count)])
            }
        }
        let pages = chunks.map { slice in
            TodoStickyPrintPage(
                householdName: householdName,
                notes: slice,
                grid: grid
            )
        }
        present(jobName: jobName, pages: pages, locale: locale)
    }

    static func printPlannerHome(
        jobName: String,
        householdName: String,
        rows: [PlannerPrintRow],
        locale: Locale
    ) {
        let pieces = rows.map { PlannerPrintPiece.row($0) }
        let pages = paginate(pieces, locale: locale, measure: { piece in
            PlannerHomePrintMeasure(piece: piece)
        }, measuredPage: { slice in
            PlannerHomePrintPage(householdName: householdName, rows: slice, fillsPage: false)
        }, page: { slice in
            PlannerHomePrintPage(householdName: householdName, rows: slice, fillsPage: true)
        })
        present(jobName: jobName, pages: pages, locale: locale)
    }

    static func printPlannerItems(
        jobName: String,
        title: String,
        open: [String],
        checked: [String],
        checkedHeading: String,
        locale: Locale
    ) {
        var pieces: [PlannerItemPrintPiece] = open.map { .item($0, checked: false) }
        if checked.isEmpty == false {
            pieces.append(.header(checkedHeading))
            pieces.append(contentsOf: checked.map { .item($0, checked: true) })
        }
        let pages = paginate(pieces, locale: locale, sticksToNext: { piece in
            if case .header = piece { return true }
            return false
        }, measure: { piece in
            PlannerItemPrintMeasure(piece: piece)
        }, measuredPage: { slice in
            PlannerItemPrintPage(title: title, pieces: slice, fillsPage: false)
        }, page: { slice in
            PlannerItemPrintPage(title: title, pieces: slice, fillsPage: true)
        })
        present(jobName: jobName, pages: pages, locale: locale)
    }

    private static func listPieces(_ sections: [TodoPrintSection]) -> [TodoListPrintPiece] {
        var pieces: [TodoListPrintPiece] = []
        for section in sections where section.tasks.isEmpty == false {
            pieces.append(.header(section.title))
            pieces.append(contentsOf: section.tasks.map { .task($0) })
        }
        return pieces
    }

    /// 先量整份内容。不超过一页就不再拆；超出时按实测高度往页面里塞，塞不下才换页。
    private static func paginate<Piece, Measure: View, Page: View>(
        _ pieces: [Piece],
        locale: Locale,
        sticksToNext: @escaping (Piece) -> Bool = { _ in false },
        measure: (Piece) -> Measure,
        measuredPage: ([Piece]) -> Page,
        page: ([Piece]) -> Page
    ) -> [Page] {
        if pieces.isEmpty {
            return [page([])]
        }
        let whole = contentHeight(of: measuredPage(pieces), locale: locale)
        if whole > 0, whole <= PrintPageMetrics.page.height {
            return [page(pieces)]
        }

        var heights = pieces.map { contentHeight(of: measure($0), locale: locale) }
        if heights.contains(where: { $0 <= 0 || $0 >= 9_000 }) {
            heights = pieces.map { _ in 56 }
        }
        let packed = pack(
            pieces,
            heights: heights,
            sticksToNext: pieces.map(sticksToNext),
            spacing: 8,
            limit: PrintPageMetrics.page.height - 48
        )
        return packed.map { page($0) }
    }

    private static func pack<Piece>(
        _ pieces: [Piece],
        heights: [CGFloat],
        sticksToNext: [Bool],
        spacing: CGFloat,
        limit: CGFloat
    ) -> [[Piece]] {
        var pages: [[Piece]] = []
        var page: [Piece] = []
        var used: CGFloat = 0
        var index = 0
        while index < pieces.count {
            let height = max(24, heights[index])
            let gap: CGFloat = page.isEmpty ? 0 : spacing
            let keepsNext = sticksToNext[index] && index + 1 < pieces.count
            let following = keepsNext ? spacing + max(24, heights[index + 1]) : 0
            if page.isEmpty == false, used + gap + height + following > limit {
                pages.append(page)
                page = []
                used = 0
                continue
            }
            let leadingGap: CGFloat = page.isEmpty ? 0 : spacing
            page.append(pieces[index])
            used += leadingGap + height
            index += 1
        }
        if page.isEmpty == false {
            pages.append(page)
        }
        return pages.isEmpty ? [[]] : pages
    }

    private static func present<V: View>(jobName: String, pages: [V], locale: Locale) {
        let images = pages.map { render($0, locale: locale) }
        FamilyDocumentPrinter.printImages(jobName: jobName, images: images)
    }

    private static func render<V: View>(_ page: V, locale: Locale) -> UIImage {
        let canvas = page
            .frame(width: PrintPageMetrics.page.width, height: PrintPageMetrics.page.height, alignment: .top)
            .background(Color.white)
            .environment(\.colorScheme, .light)
            .environment(\.locale, locale)
        let renderer = ImageRenderer(content: canvas)
        renderer.proposedSize = ProposedViewSize(
            width: PrintPageMetrics.page.width,
            height: PrintPageMetrics.page.height
        )
        renderer.scale = 2
        renderer.isOpaque = true
        return renderer.uiImage ?? UIImage()
    }

    private static func contentHeight<V: View>(of view: V, locale: Locale) -> CGFloat {
        let root = view
            .frame(width: PrintPageMetrics.page.width, alignment: .topLeading)
            .environment(\.colorScheme, .light)
            .environment(\.locale, locale)
        let host = UIHostingController(rootView: root)
        host.safeAreaRegions = []
        host.view.backgroundColor = .clear
        let size = host.sizeThatFits(
            in: CGSize(width: PrintPageMetrics.page.width, height: 10_000)
        )
        guard size.height.isFinite, size.height > 0, size.height < 9_000 else { return 0 }
        return size.height
    }
}

private enum PrintPageMetrics {
    static let page = CGSize(width: 595, height: 842)
}

// MARK: - List

private enum TodoListPrintPiece {
    case header(String)
    case task(TodoPrintTask)
}

private struct TodoListPrintPage: View {
    let householdName: String
    let pieces: [TodoListPrintPiece]
    var fillsPage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(householdName)
                .font(.caption)
                .foregroundStyle(.secondary)
            if pieces.isEmpty {
                Spacer(minLength: 0)
                Text(L10n.Common.nothingToPrint.string(locale: locale))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    switch piece {
                    case .header(let title):
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 6)
                    case .task(let task):
                        TodoFlexibleRow(
                            task: task.task,
                            displayTitle: task.title,
                            forWhomAvatars: task.avatars,
                            deadlineLabel: task.deadline,
                            style: .active,
                            hasAttachments: task.hasAttachments,
                            onToggleComplete: {}
                        )
                    }
                }
                if fillsPage {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : nil, alignment: .top)
        .environment(\.locale, locale)
    }

    @Environment(\.locale) private var locale
}

private struct TodoListPrintMeasure: View {
    let piece: TodoListPrintPiece

    var body: some View {
        switch piece {
        case .header(let title):
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.top, 6)
        case .task(let task):
            TodoFlexibleRow(
                task: task.task,
                displayTitle: task.title,
                forWhomAvatars: task.avatars,
                deadlineLabel: task.deadline,
                style: .active,
                hasAttachments: task.hasAttachments,
                onToggleComplete: {}
            )
            .padding(.horizontal, 22)
        }
    }
}

// MARK: - Sticky notes

private struct StickyPrintGrid {
    let columns: Int
    let noteSize: CGSize
    let gap: CGFloat
    let perPage: Int

    static func make() -> StickyPrintGrid {
        let columns = 4
        let gap: CGFloat = 16
        let margin: CGFloat = 18
        let header: CGFloat = 22
        let usableWidth = PrintPageMetrics.page.width - margin * 2
        let noteWidth = (usableWidth - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let noteHeight = noteWidth * 158 / 148
        let usableHeight = PrintPageMetrics.page.height - margin * 2 - header
        var rows = max(1, Int((usableHeight + gap) / (noteHeight + gap)))
        while rows > 1 {
            let used = header + margin * 2 + CGFloat(rows) * noteHeight + CGFloat(max(0, rows - 1)) * gap
            if used <= PrintPageMetrics.page.height { break }
            rows -= 1
        }
        return StickyPrintGrid(
            columns: columns,
            noteSize: CGSize(width: noteWidth, height: noteHeight),
            gap: gap,
            perPage: columns * rows
        )
    }
}

private struct TodoStickyPrintPage: View {
    let householdName: String
    let notes: [TodoPrintTask]
    let grid: StickyPrintGrid

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(householdName)
                .font(.caption)
                .foregroundStyle(.secondary)
            if notes.isEmpty {
                Spacer()
                Text(L10n.Common.nothingToPrint.string(locale: locale))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                let rows = stride(from: 0, to: notes.count, by: grid.columns).map { start in
                    Array(notes[start..<min(start + grid.columns, notes.count)])
                }
                VStack(alignment: .leading, spacing: grid.gap) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: grid.gap) {
                            ForEach(row) { note in
                                TodoPrintStickyNote(note: note)
                                    .frame(width: grid.noteSize.width, height: grid.noteSize.height)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(stickyBoardBackground)
    }

    @Environment(\.locale) private var locale

    private var stickyBoardBackground: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.96)))
            let step: CGFloat = 28
            var path = Path()
            stride(from: 0, through: size.width, by: step).forEach { x in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0, through: size.height, by: step).forEach { y in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(Color.black.opacity(0.04)), lineWidth: 0.5)
        }
    }
}

private struct TodoPrintStickyNote: View {
    let note: TodoPrintTask

    private var look: StickyPrintLook {
        StickyPrintLook.stable(id: note.id, theme: note.theme, backgroundHex: note.backgroundHex)
    }

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(look.paper)
                .overlay {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(look.titleInk ?? .primary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                ForEach(Array(note.details.prefix(2).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.caption2)
                        .foregroundStyle(look.detailInk ?? .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 10)
            Circle()
                .fill(look.pin)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle().stroke(Color.white.opacity(0.7), lineWidth: 1)
                }
                .offset(y: -6)
        }
        .rotationEffect(.degrees(look.rotation))
        .shadow(color: .black.opacity(0.08), radius: 3, x: 1, y: 2)
    }
}

private struct StickyPrintLook {
    let paper: Color
    let titleInk: Color?
    let detailInk: Color?
    let pin: Color
    let rotation: Double

    static func stable(id: UUID, theme: Color, backgroundHex: String?) -> StickyPrintLook {
        let seed = id.uuidString.utf8.reduce(0) { $0 &* 31 &+ Int($1) }
        let strengths: [Double] = [0.62, 0.68, 0.74, 0.82, 0.66, 0.72]
        let strength = strengths[abs(seed) % strengths.count]
        let pinPalette: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal,
            .cyan, .blue, .indigo, .purple, .pink, .brown
        ]
        let ink = Color.taskCardInkColors(forBackgroundHex: backgroundHex)
        let paper = Color.taskCardCustomColor(fromHex: backgroundHex) ?? theme.opacity(strength)
        return StickyPrintLook(
            paper: paper,
            titleInk: ink?.title,
            detailInk: ink?.detail,
            pin: pinPalette[abs(seed / 7) % pinPalette.count],
            rotation: Double((abs(seed / 11) % 11) - 5) * 0.85
        )
    }
}

// MARK: - Planner

private enum PlannerPrintPiece {
    case row(PlannerPrintRow)
}

private struct PlannerHomePrintPage: View {
    let householdName: String
    let rows: [PlannerPrintPiece]
    var fillsPage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(householdName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            if rows.isEmpty {
                Spacer()
                Text(L10n.Common.nothingToPrint.string(locale: locale))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, piece in
                    if case .row(let row) = piece {
                        plannerRow(row)
                        if index < rows.count - 1 {
                            Divider().padding(.leading, 50)
                        }
                    }
                }
                if fillsPage {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : nil, alignment: .top)
    }

    @Environment(\.locale) private var locale

    private func plannerRow(_ row: PlannerPrintRow) -> some View {
        HStack(spacing: 14) {
            Image(systemName: row.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.ColorToken.accent)
                .frame(width: 36, height: 36)
                .background(
                    AppTheme.ColorToken.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(row.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }
}

private struct PlannerHomePrintMeasure: View {
    let piece: PlannerPrintPiece

    var body: some View {
        if case .row(let row) = piece {
            HStack {
                Text(row.title).font(.body.weight(.semibold))
                Text(row.subtitle).font(.caption)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }
}

private enum PlannerItemPrintPiece {
    case header(String)
    case item(String, checked: Bool)
}

private struct PlannerItemPrintPage: View {
    let title: String
    let pieces: [PlannerItemPrintPiece]
    var fillsPage: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title2.weight(.bold))
                .lineLimit(2)
            if pieces.isEmpty {
                Spacer()
                Text(L10n.Common.nothingToPrint.string(locale: locale))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(Array(pieces.enumerated()), id: \.offset) { _, piece in
                    switch piece {
                    case .header(let heading):
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                    case .item(let title, let checked):
                        HStack(spacing: 12) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(checked ? Color.green : Color.secondary)
                            Text(title)
                                .font(.body)
                                .foregroundStyle(checked ? .secondary : .primary)
                                .strikethrough(checked)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 4)
                    }
                }
                if fillsPage {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: fillsPage ? .infinity : nil, alignment: .top)
    }

    @Environment(\.locale) private var locale
}

private struct PlannerItemPrintMeasure: View {
    let piece: PlannerItemPrintPiece

    var body: some View {
        switch piece {
        case .header(let heading):
            Text(heading)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.top, 8)
        case .item(let itemTitle, let checked):
            HStack {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                Text(itemTitle)
                    .font(.body)
                    .strikethrough(checked)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 4)
        }
    }
}
