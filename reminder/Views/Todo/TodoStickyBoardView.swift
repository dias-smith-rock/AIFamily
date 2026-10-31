import SwiftUI

/// 白板便签模式：正面近期 / 背面远期；可翻转；角落垃圾桶与书架。
struct TodoStickyBoardView: View {
    let nearTasks: [FamilyTask]
    let farTasks: [FamilyTask]
    let overdueCount: Int
    let completedCount: Int
    let displayTitle: (FamilyTask) -> String
    let forWhomAvatars: (FamilyTask) -> [TaskCardAvatarSource]
    /// 标题之外的次要信息（至多 2 条，与标题合计 ≤ 3）。
    let detailLines: (FamilyTask) -> [String]
    let hasAttachments: (FamilyTask) -> Bool
    let isCompletionChecked: (UUID) -> Bool
    let isFlying: (UUID) -> Bool
    let isInteractionLocked: (UUID) -> Bool
    let onToggleComplete: (FamilyTask) -> Void
    let onOpen: (FamilyTask) -> Void
    let onOpenOverdueBin: () -> Void
    let onOpenCompletedArchive: () -> Void
    let onDropComplete: (FamilyTask) -> Void
    let onDropDelete: (FamilyTask) -> Void

    @State private var positions: [UUID: CGPoint] = [:]
    @State private var draggingID: UUID?
    @State private var dragStartBoardPosition: CGPoint?
    @State private var frontmostID: UUID?
    @State private var zOrderRanks: [UUID: Int] = [:]
    @State private var zOrderCounter: Int = 0
    /// 正方形白板：按 10×10 可平铺约 100 张便签（见 `BoardMetrics`）。
    @State private var boardSize: CGSize = BoardMetrics.squareSize

    @State private var scale: CGFloat = 1
    @State private var committedScale: CGFloat = 1
    @State private var boardOffset: CGSize = .zero
    @State private var boardPanAnchor: CGSize?
    @State private var viewportSize: CGSize = .zero
    /// Duo 折痕（视口坐标）；无 SDK / 无折痕时为 `nil`。
    @State private var divisionFrame: CGRect?
    @State private var trashFrameGlobal: CGRect = .zero
    @State private var shelfFrameGlobal: CGRect = .zero
    @State private var activeDropTarget: StickyDropTarget?
    /// 浮起便签的视口缩放。悬停垃圾桶/书架时收到与落点相同的大小，离开后回到拖起尺寸。
    @State private var liftScale: CGFloat = 1
    /// 拖到角落后浮在 bin 之上的便签会话（确认删除 / 完成消失 / 取消回位）。
    @State private var liftSession: NoteLiftSession?
    @State private var showStickyDeleteConfirm = false
    /// 松手回板后触发图钉钉入动画的便签 id。
    @State private var pinInsertingID: UUID?
    @EnvironmentObject private var appSettings: AppSettingsManager
    /// 仅首次进入便签模式时自动适配缩放，之后由用户手势控制。
    @State private var didPerformInitialFit = false
    private let pinInsertDuration: TimeInterval = 0.2
    /// 白板绕 Y 轴累计旋转角；每 +180° 翻一面。
    @State private var boardFlipDegrees: Double = 0
    @State private var isBoardFlipping = false

    private let noteSize = BoardMetrics.noteSize
    private let positionsStorageKey = "todo_sticky_note_positions"
    private let scaleStorageKey = "todo_sticky_board_scale"
    private let scaleRange: ClosedRange<CGFloat> = 0.45...2.4
    private let boardSpace = "todoStickyBoardSpace"
    private let boardFlipDuration: TimeInterval = 1.0
    private let dropFadeDuration: TimeInterval = 0.8
    private let dropReturnDuration: TimeInterval = 0.5

    private enum StickyDropTarget: Equatable {
        case trash
        case shelf
    }

    private struct NoteLiftSession: Equatable {
        enum Phase: Equatable {
            case dragging
            case awaitingDeleteConfirm
            case returningHome
            case fadingOut
        }

        let task: FamilyTask
        var boardPoint: CGPoint
        let homeBoardPoint: CGPoint
        var opacity: Double
        /// 相对拖起态的额外缩放（消失时收到接近 0）。
        var shrink: CGFloat
        var phase: Phase
    }

    private var isDropResolutionInProgress: Bool {
        guard let phase = liftSession?.phase else { return false }
        return phase != .dragging
    }

    private var canFlipBoard: Bool {
        nearTasks.isEmpty == false && farTasks.isEmpty == false
    }

    /// 旋转过半后切换为背面内容（避免翻面中途文字长时间镜像）。
    private var showingFarSide: Bool {
        var degrees = boardFlipDegrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return degrees > 90 && degrees < 270
    }

    private var displayedTasks: [FamilyTask] {
        if canFlipBoard {
            return showingFarSide ? farTasks : nearTasks
        }
        return nearTasks + farTasks
    }

    var body: some View {
        GeometryReader { geo in
            let viewport = geo.size

            let metrics = geo.duoLayoutMetrics(horizontalSizeClass: nil)
            let divisionInsets = metrics.divisionAvoidanceInsets

            ZStack {
                // 默认与白板同色；自定义页面背景时透出 Schedule/Todo 共用底图。
                boardChromeFill.ignoresSafeArea(edges: .bottom)

                // 先把布局尺寸压回视口，避免 2000×2000 白板把 ZStack 撑乱，导致角落控件被居中/裁切。
                boardLayer(viewport: viewport)
                    .scaleEffect(scale, anchor: .center)
                    .offset(boardOffset)
                    .frame(width: viewport.width, height: viewport.height)
                    .clipped()
                    .rotation3DEffect(
                        .degrees(boardFlipDegrees),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.55
                    )
                    // 背面朝向镜头时水平镜像，保证文字正向可读。
                    .scaleEffect(x: showingFarSide ? -1 : 1, y: 1)
                    .gesture(boardPanGesture)
                    .simultaneousGesture(boardMagnifyGesture)
                    .allowsHitTesting(isBoardFlipping == false && isDropResolutionInProgress == false)

                cornerBinsOverlay
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    // 侧栏 Tab / 刘海安全区：避免 bin 压到系统 chrome。
                    .duoCanvasChromePadding(extra: divisionInsets)
                    .zIndex(10_000)

                if canFlipBoard {
                    flipBoardButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 18)
                        .zIndex(10_001)
                }

                if showsFitAllNotesButton {
                    fitAllNotesButton
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                        .padding(.leading, 20)
                        .padding(.bottom, 20)
                        .duoCanvasChromePadding(extra: divisionInsets)
                        .zIndex(10_001)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }

                // 拖到垃圾桶/书架时浮在 bin 上方，避免被角标挡住。
                if let session = liftSession {
                    liftedStickyNote(for: session)
                        .position(viewportPoint(forBoardPoint: session.boardPoint))
                        .opacity(session.opacity)
                        .zIndex(20_000)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .alert(
                L10n.Schedule.deleteTask,
                isPresented: $showStickyDeleteConfirm
            ) {
                Button(L10n.Schedule.deleteThisTaskOnly, role: .destructive) {
                    confirmStickyDelete()
                }
                Button(L10n.Common.cancel, role: .cancel) {
                    cancelStickyDelete()
                }
            } message: {
                Text(L10n.Common.thisActionCannotBeUndone2.localized)
            }
            .onAppear {
                viewportSize = viewport
                divisionFrame = metrics.divisionFrame
                loadPositions()
                syncBoardSideAvailability()
                ensurePositions(for: displayedTasks, viewport: viewport)
                expandBoardIfNeeded(viewport: viewport)
                performInitialFitIfNeeded(in: viewport)
            }
            .onChange(of: viewport) { oldViewport, newViewport in
                let previous = viewportSize.width > 1 ? viewportSize : oldViewport
                viewportSize = newViewport
                divisionFrame = geo.duoDivisionFrame
                expandBoardIfNeeded(viewport: newViewport)
                // 首帧 Geometry 可能为 0，等视口有效后再做唯一一次自动适配。
                performInitialFitIfNeeded(in: newViewport)
                // Duo 开合 / 窗口缩放：保留用户缩放，仅重新夹紧并尽量让内容回到视野。
                if didPerformInitialFit, previous.width > 1, previous.height > 1,
                   newViewport.width > 1, newViewport.height > 1 {
                    let oldAspect = previous.width / previous.height
                    let newAspect = newViewport.width / newViewport.height
                    if abs(oldAspect - newAspect) > 0.12
                        || abs(previous.width - newViewport.width) > 80
                        || abs(previous.height - newViewport.height) > 80 {
                        boardOffset = contentCenteringOffset(scale: scale, viewport: newViewport)
                    } else {
                        boardOffset = clampedBoardOffset(boardOffset, scale: scale, viewport: newViewport)
                    }
                } else {
                    boardOffset = clampedBoardOffset(boardOffset, scale: scale, viewport: newViewport)
                }
            }
            .onChange(of: nearTasks.map(\.id)) { _, _ in
                syncBoardSideAvailability()
                ensurePositions(for: displayedTasks, viewport: viewport)
                prunePositions(keeping: Set((nearTasks + farTasks).map(\.id)))
                expandBoardIfNeeded(viewport: viewport)
            }
            .onChange(of: farTasks.map(\.id)) { _, _ in
                syncBoardSideAvailability()
                ensurePositions(for: displayedTasks, viewport: viewport)
                prunePositions(keeping: Set((nearTasks + farTasks).map(\.id)))
                expandBoardIfNeeded(viewport: viewport)
            }
        }
    }

    private var flipBoardButton: some View {
        Button {
            flipWhiteboard()
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(AppTheme.ColorToken.surfaceMuted)
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 3)
                }
                .overlay {
                    Circle()
                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(isBoardFlipping)
        .opacity(isBoardFlipping ? 0.55 : 1)
        .accessibilityLabel(
            showingFarSide ? L10n.Todo.showNearTermTasks : L10n.Todo.showLaterTasks
        )
    }

    /// 有便签落在视口外时，左下角提供一键缩放适配。
    private var showsFitAllNotesButton: Bool {
        guard displayedTasks.isEmpty == false else { return false }
        guard viewportSize.width > 1, viewportSize.height > 1 else { return false }
        guard isBoardFlipping == false else { return false }
        return areAllDisplayedNotesVisible(in: viewportSize) == false
    }

    private var fitAllNotesButton: some View {
        Button {
            fitAllNotes(in: viewportSize, animated: true)
            savePersistedScale(scale)
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(AppTheme.ColorToken.accent, in: Circle())
                .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Todo.fitAllNotes)
    }

    /// 当前面全部便签（含缩放后的尺寸）是否完全落在可用视口内。
    private func areAllDisplayedNotesVisible(in viewport: CGSize) -> Bool {
        // 预留顶栏 bins / 底部 FAB 与翻面按钮的安全边距。
        let visibleBounds = CGRect(
            x: 10,
            y: 82,
            width: max(viewport.width - 20 - 72, 0),
            height: max(viewport.height - 82 - 88, 0)
        )
        guard visibleBounds.width > 40, visibleBounds.height > 40 else { return true }

        let safeScale = max(scale, 0.01)
        let screenNoteSize = CGSize(
            width: noteSize.width * safeScale,
            height: noteSize.height * safeScale
        )

        for task in displayedTasks {
            let boardPoint = resolvedPosition(for: task, viewport: viewport)
            let center = viewportPoint(forBoardPoint: boardPoint)
            let noteRect = CGRect(
                x: center.x - screenNoteSize.width / 2,
                y: center.y - screenNoteSize.height / 2,
                width: screenNoteSize.width,
                height: screenNoteSize.height
            )
            if visibleBounds.contains(noteRect) == false {
                return false
            }
        }
        return true
    }

    private func flipWhiteboard() {
        guard canFlipBoard, isBoardFlipping == false else { return }
        isBoardFlipping = true
        withAnimation(.easeInOut(duration: boardFlipDuration)) {
            boardFlipDegrees += 180
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(boardFlipDuration * 1_000_000_000))
            isBoardFlipping = false
        }
    }

    private func syncBoardSideAvailability() {
        if canFlipBoard == false {
            boardFlipDegrees = 0
            isBoardFlipping = false
        }
    }

    // MARK: - Board

    private func boardLayer(viewport: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            whiteboardBackground
                .frame(width: boardSize.width, height: boardSize.height)
                .contentShape(Rectangle())
                // 仅空白纸面：双击放大（便签会先命中，不会进到这里）。
                .onTapGesture(count: 2) { location in
                    zoomIn(towardBoardPoint: location)
                }

            ForEach(displayedTasks) { task in
                stickyNote(for: task)
                    .position(resolvedPosition(for: task, viewport: viewport))
                    .zIndex(stackingZIndex(for: task.id))
            }
        }
        .frame(width: boardSize.width, height: boardSize.height)
        .coordinateSpace(name: boardSpace)
    }

    private var usesSharedPageBackground: Bool {
        appSettings.scheduleBackgroundMode != .systemDefault
    }

    private var boardChromeFill: Color {
        usesSharedPageBackground ? .clear : AppTheme.ColorToken.surface
    }

    private var whiteboardBackground: some View {
        ZStack {
            boardChromeFill
            Color.primary.opacity(usesSharedPageBackground ? 0.04 : 0.025)

            Canvas { context, size in
                let step = BoardMetrics.gridStep
                var path = Path()
                stride(from: 0.0, through: Double(size.width), by: Double(step)).forEach { x in
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                stride(from: 0.0, through: Double(size.height), by: Double(step)).forEach { y in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                let gridOpacity = usesSharedPageBackground ? 0.14 : 0.07
                context.stroke(path, with: .color(.primary.opacity(gridOpacity)), lineWidth: 1)
            }
        }
    }

    // MARK: - Corner bins (viewport-fixed)

    private var cornerBinsOverlay: some View {
        HStack(alignment: .top, spacing: 12) {
            StickyBoardTrashBin(
                count: overdueCount,
                isHighlighted: activeDropTarget == .trash,
                onTap: onOpenOverdueBin
            )
            .background(globalFrameReader(into: $trashFrameGlobal))

            Spacer(minLength: 0)

            StickyBoardBookshelf(
                count: completedCount,
                isHighlighted: activeDropTarget == .shelf,
                onTap: onOpenCompletedArchive
            )
            .background(globalFrameReader(into: $shelfFrameGlobal))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        // 拖动 / 确认投放过程中不拦截触点，便于命中投放区或避免误点。
        .allowsHitTesting(draggingID == nil && isDropResolutionInProgress == false)
    }

    private func globalFrameReader(into binding: Binding<CGRect>) -> some View {
        GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Color.clear
                .onAppear { binding.wrappedValue = frame }
                .onChange(of: frame) { _, newFrame in
                    binding.wrappedValue = newFrame
                }
        }
    }

    // MARK: - Note

    private func stickyNote(for task: FamilyTask) -> some View {
        let look = StickyNoteLook.stable(for: task.id, theme: task.cardThemeAccentColor)
        let flying = isFlying(task.id)
        let lifted = liftSession?.task.id == task.id
        let dragging = draggingID == task.id

        return TodoStickyNoteCard(
            look: look,
            title: displayTitle(task),
            detailLines: Array(detailLines(task).prefix(2)),
            avatars: forWhomAvatars(task),
            hasAttachments: hasAttachments(task),
            isDragging: dragging || lifted,
            isPinInserting: pinInsertingID == task.id,
            onActivate: { bringToFront(task.id) },
            onOpen: {
                bringToFront(task.id)
                onOpen(task)
            }
        )
        .frame(width: noteSize.width, height: noteSize.height)
        .rotationEffect(.degrees((dragging || lifted) ? 0 : look.rotationDegrees))
        .scaleEffect(dragging ? 1.08 : (flying ? 0.15 : 1))
        .opacity((flying || lifted) ? 0 : 1)
        .scaleEffect(dropHoverScale(for: task.id), anchor: .center)
        // 触点落在便签上 → 拖便签；空白处由白板 pan 手势处理。
        .gesture(noteMoveGesture(for: task))
        .allowsHitTesting(
            flying == false
                && lifted == false
                && isDropResolutionInProgress == false
                && isInteractionLocked(task.id) == false
        )
    }

    private func liftedStickyNote(for session: NoteLiftSession) -> some View {
        let task = session.task
        let look = StickyNoteLook.stable(for: task.id, theme: task.cardThemeAccentColor)
        return TodoStickyNoteCard(
            look: look,
            title: displayTitle(task),
            detailLines: Array(detailLines(task).prefix(2)),
            avatars: forWhomAvatars(task),
            hasAttachments: hasAttachments(task),
            isDragging: true,
            isPinInserting: false,
            onActivate: {},
            onOpen: {}
        )
        .frame(width: noteSize.width, height: noteSize.height)
        .scaleEffect(liftScale * session.shrink)
        .shadow(
            color: .black.opacity(0.28 * session.opacity),
            radius: 14 * session.shrink * liftShadowFactor,
            y: 6 * session.shrink * liftShadowFactor
        )
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: liftScale)
    }

    /// 拖起时略放大，并跟上白板缩放，使浮起便签与板上视觉大小一致。
    private var draggingLiftScale: CGFloat {
        1.08 * max(scale, 0.01)
    }

    /// 缩进落点后阴影按同样比例收小，避免小卡片拖着一大圈影子。
    private var liftShadowFactor: CGFloat {
        min(liftScale / draggingLiftScale, 1)
    }

    /// 把便签外框收进垃圾桶或书架的实测尺寸（保持比例，只缩小不放大）。
    private func dropTargetFitScale(for target: StickyDropTarget) -> CGFloat {
        let frame: CGRect
        switch target {
        case .trash:
            frame = trashFrameGlobal
        case .shelf:
            frame = shelfFrameGlobal
        }
        guard frame.width > 1, frame.height > 1 else { return draggingLiftScale }
        let fit = min(frame.width / noteSize.width, frame.height / noteSize.height)
        return min(max(fit, 0.18), draggingLiftScale)
    }

    private func dropHoverScale(for id: UUID) -> CGFloat {
        guard draggingID == id, activeDropTarget != nil else { return 1 }
        return 0.92
    }

    /// 白板坐标 → 视口坐标（含缩放、平移与翻面镜像）。
    private func viewportPoint(forBoardPoint boardPoint: CGPoint) -> CGPoint {
        let safeScale = max(scale, 0.01)
        let boardCenter = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        var dx = (boardPoint.x - boardCenter.x) * safeScale
        let dy = (boardPoint.y - boardCenter.y) * safeScale
        if showingFarSide {
            dx = -dx
        }
        return CGPoint(
            x: viewportCenter.x + boardOffset.width + dx,
            y: viewportCenter.y + boardOffset.height + dy
        )
    }

    /// 从便签上起拖：移动便签；松手落在书架=完成，垃圾桶=删除。轻点仍走卡片 `onTapGesture`。
    private func noteMoveGesture(for task: FamilyTask) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { drag in
                guard isDropResolutionInProgress == false else { return }
                if draggingID != task.id {
                    let home = positions[task.id] ?? resolvedPosition(for: task, viewport: viewportSize)
                    draggingID = task.id
                    dragStartBoardPosition = home
                    liftScale = draggingLiftScale
                    liftSession = NoteLiftSession(
                        task: task,
                        boardPoint: home,
                        homeBoardPoint: home,
                        opacity: 1,
                        shrink: 1,
                        phase: .dragging
                    )
                    bringToFront(task.id)
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                }
                guard let start = dragStartBoardPosition else { return }
                let safeScale = max(scale, 0.01)
                let next = clampPoint(
                    CGPoint(
                        x: start.x + drag.translation.width / safeScale,
                        y: start.y + drag.translation.height / safeScale
                    )
                )
                positions[task.id] = next
                if var session = liftSession, session.task.id == task.id {
                    session.boardPoint = next
                    liftSession = session
                }
                updateDropTarget(atGlobal: drag.location)
            }
            .onEnded { _ in
                let target = activeDropTarget
                let draggedID = draggingID

                guard let draggedID, draggedID == task.id else { return }
                guard liftSession?.task.id == task.id else {
                    draggingID = nil
                    dragStartBoardPosition = nil
                    activeDropTarget = nil
                    return
                }

                switch target {
                case .shelf:
                    draggingID = nil
                    dragStartBoardPosition = nil
                    beginFadeOutThenComplete(task)
                case .trash:
                    draggingID = nil
                    dragStartBoardPosition = nil
                    if var session = liftSession, session.task.id == task.id {
                        session.phase = .awaitingDeleteConfirm
                        liftSession = session
                    }
                    showStickyDeleteConfirm = true
                case nil:
                    draggingID = nil
                    dragStartBoardPosition = nil
                    liftSession = nil
                    activeDropTarget = nil
                    savePositions()
                    expandBoardIfNeeded(viewport: viewportSize)
                    boardOffset = clampedBoardOffset(boardOffset, scale: scale, viewport: viewportSize)
                    playPinInsertAnimation(for: task.id)
                }
            }
    }

    private func playPinInsertAnimation(for id: UUID) {
        pinInsertingID = id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(pinInsertDuration * 1_000_000_000))
            if pinInsertingID == id {
                pinInsertingID = nil
            }
        }
    }

    private func beginFadeOutThenComplete(_ task: FamilyTask) {
        guard var session = liftSession, session.task.id == task.id else {
            activeDropTarget = nil
            onDropComplete(task)
            return
        }
        animateLiftSessionFadeOut(&session)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dropFadeDuration * 1_000_000_000))
            positions.removeValue(forKey: task.id)
            savePositions()
            liftSession = nil
            activeDropTarget = nil
            onDropComplete(task)
        }
    }

    private func confirmStickyDelete() {
        guard var session = liftSession, session.phase == .awaitingDeleteConfirm else {
            liftSession = nil
            activeDropTarget = nil
            return
        }
        let task = session.task
        animateLiftSessionFadeOut(&session)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dropFadeDuration * 1_000_000_000))
            positions.removeValue(forKey: task.id)
            savePositions()
            liftSession = nil
            activeDropTarget = nil
            onDropDelete(task)
        }
    }

    private func animateLiftSessionFadeOut(_ session: inout NoteLiftSession) {
        session.phase = .fadingOut
        session.opacity = 0
        session.shrink = 0.05
        withAnimation(.easeOut(duration: dropFadeDuration)) {
            liftSession = session
        }
    }

    private func cancelStickyDelete() {
        guard var session = liftSession, session.phase == .awaitingDeleteConfirm else {
            liftSession = nil
            activeDropTarget = nil
            return
        }
        let home = session.homeBoardPoint
        let taskID = session.task.id
        session.phase = .returningHome
        session.boardPoint = home
        withAnimation(.easeInOut(duration: dropReturnDuration)) {
            liftSession = session
            liftScale = draggingLiftScale
            activeDropTarget = nil
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(dropReturnDuration * 1_000_000_000))
            positions[taskID] = home
            savePositions()
            liftSession = nil
            playPinInsertAnimation(for: taskID)
        }
    }

    private func performInitialFitIfNeeded(in viewport: CGSize) {
        guard didPerformInitialFit == false else { return }
        guard viewport.width > 1, viewport.height > 1 else { return }
        didPerformInitialFit = true
        if let savedScale = loadPersistedScale() {
            let clamped = clampedScale(savedScale, viewport: viewport)
            applyScale(clamped, centeringContentIn: viewport, animated: false)
        } else {
            fitAllNotes(in: viewport, animated: false)
        }
    }

    private func updateDropTarget(atGlobal point: CGPoint) {
        let pad: CGFloat = 12
        let next: StickyDropTarget?
        if trashFrameGlobal.insetBy(dx: -pad, dy: -pad).contains(point) {
            next = .trash
        } else if shelfFrameGlobal.insetBy(dx: -pad, dy: -pad).contains(point) {
            next = .shelf
        } else {
            next = nil
        }
        guard next != activeDropTarget else { return }
        let nextScale = next.map { dropTargetFitScale(for: $0) } ?? draggingLiftScale
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            activeDropTarget = next
            liftScale = nextScale
        }
        if next != nil {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
        }
    }

    private func bringToFront(_ id: UUID) {
        guard frontmostID != id else { return }
        frontmostID = id
        zOrderCounter += 1
        zOrderRanks[id] = zOrderCounter
    }

    private func stackingZIndex(for id: UUID) -> Double {
        if draggingID == id { return 1_000_000 }
        if let rank = zOrderRanks[id] { return Double(rank) }
        return Double(abs(id.hashValue % 1000))
    }

    /// 起点在空白白板（非便签）上时平移屏幕。
    private var boardPanGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                // 正在拖便签时不平移白板。
                guard draggingID == nil else {
                    boardPanAnchor = nil
                    return
                }
                if boardPanAnchor == nil {
                    boardPanAnchor = boardOffset
                }
                guard let anchor = boardPanAnchor else { return }
                let proposed = CGSize(
                    width: anchor.width + value.translation.width,
                    height: anchor.height + value.translation.height
                )
                boardOffset = clampedBoardOffset(proposed, scale: scale, viewport: viewportSize)
            }
            .onEnded { _ in
                boardPanAnchor = nil
                boardOffset = clampedBoardOffset(boardOffset, scale: scale, viewport: viewportSize)
            }
    }

    private var boardMagnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard draggingID == nil else { return }
                let next = committedScale * value.magnification
                let clampedScale = min(max(next, minimumScaleToFillViewport(viewportSize)), scaleRange.upperBound)
                scale = clampedScale
                boardOffset = clampedBoardOffset(boardOffset, scale: clampedScale, viewport: viewportSize)
            }
            .onEnded { _ in
                committedScale = scale
                boardOffset = clampedBoardOffset(boardOffset, scale: scale, viewport: viewportSize)
                savePersistedScale(scale)
            }
    }

    /// 双击空白处：以点击点为锚放大一档。
    private func zoomIn(towardBoardPoint boardPoint: CGPoint, factor: CGFloat = 1.5) {
        guard draggingID == nil, isBoardFlipping == false else { return }
        guard viewportSize.width > 1, viewportSize.height > 1 else { return }

        let minScale = minimumScaleToFillViewport(viewportSize)
        let nextScale = min(max(scale * factor, minScale), scaleRange.upperBound)
        guard abs(nextScale - scale) > 0.01 else { return }

        let anchorViewport = viewportPoint(forBoardPoint: boardPoint)
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        var dx = (boardPoint.x - boardSize.width / 2) * nextScale
        let dy = (boardPoint.y - boardSize.height / 2) * nextScale
        if showingFarSide {
            dx = -dx
        }
        let proposedOffset = CGSize(
            width: anchorViewport.x - viewportCenter.x - dx,
            height: anchorViewport.y - viewportCenter.y - dy
        )

        withAnimation(.easeInOut(duration: 0.25)) {
            scale = nextScale
            committedScale = nextScale
            boardOffset = clampedBoardOffset(proposedOffset, scale: nextScale, viewport: viewportSize)
        }
        savePersistedScale(nextScale)
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    /// 缩放后白板仍盖住视口：限制平移，不露出灰边。
    private func clampedBoardOffset(_ proposed: CGSize, scale: CGFloat, viewport: CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }
        let scaledW = boardSize.width * scale
        let scaledH = boardSize.height * scale
        let maxX = max((scaledW - viewport.width) / 2, 0)
        let maxY = max((scaledH - viewport.height) / 2, 0)
        return CGSize(
            width: min(max(proposed.width, -maxX), maxX),
            height: min(max(proposed.height, -maxY), maxY)
        )
    }

    private func minimumScaleToFillViewport(_ viewport: CGSize) -> CGFloat {
        guard boardSize.width > 0, boardSize.height > 0, viewport.width > 0, viewport.height > 0 else {
            return scaleRange.lowerBound
        }
        let fill = max(viewport.width / boardSize.width, viewport.height / boardSize.height)
        return min(max(fill, scaleRange.lowerBound), scaleRange.upperBound)
    }

    /// 让全部便签落入可视区域，四周仅留约 3 个小方格边距。
    private func fitAllNotes(in viewport: CGSize, animated: Bool) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        expandBoardIfNeeded(viewport: viewport)

        let apply = {
            let visibleTasks = displayedTasks
            guard visibleTasks.isEmpty == false else {
                let fill = minimumScaleToFillViewport(viewport)
                scale = fill
                committedScale = fill
                boardOffset = .zero
                return
            }

            guard let union = contentUnionRect(for: visibleTasks, viewport: viewport) else { return }
            let contentW = max(union.width, noteSize.width)
            let contentH = max(union.height, noteSize.height)

            let margin = BoardMetrics.gridStep * CGFloat(BoardMetrics.fitEdgeGridCount)
            let availW = max(viewport.width - margin * 2, 80)
            let availH = max(viewport.height - margin * 2, 80)

            // 优先保证全部便签可见；四周仅留约 3 个小方格。
            let fit = min(availW / contentW, availH / contentH)
            let nextScale = min(max(fit, scaleRange.lowerBound), scaleRange.upperBound)
            applyScale(nextScale, centeringContentIn: viewport, animated: false)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.28), apply)
        } else {
            apply()
        }
    }

    private func applyScale(
        _ nextScale: CGFloat,
        centeringContentIn viewport: CGSize,
        animated: Bool
    ) {
        let apply = {
            scale = nextScale
            committedScale = nextScale
            boardOffset = contentCenteringOffset(scale: nextScale, viewport: viewport)
        }
        if animated {
            withAnimation(.easeInOut(duration: 0.28), apply)
        } else {
            apply()
        }
    }

    private func contentUnionRect(for tasks: [FamilyTask], viewport: CGSize) -> CGRect? {
        guard tasks.isEmpty == false else { return nil }
        let rects = tasks.map { task -> CGRect in
            let center = resolvedPosition(for: task, viewport: viewport)
            return CGRect(
                x: center.x - noteSize.width / 2,
                y: center.y - noteSize.height / 2,
                width: noteSize.width,
                height: noteSize.height
            )
        }
        return rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    }

    private func contentCenteringOffset(scale nextScale: CGFloat, viewport: CGSize) -> CGSize {
        guard let union = contentUnionRect(for: displayedTasks, viewport: viewport) else {
            return .zero
        }
        let contentCenter = CGPoint(x: union.midX, y: union.midY)
        let boardCenter = CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        let rawOffset = CGSize(
            width: (boardCenter.x - contentCenter.x) * nextScale,
            height: (boardCenter.y - contentCenter.y) * nextScale
        )
        return clampedBoardOffset(rawOffset, scale: nextScale, viewport: viewport)
    }

    private func clampedScale(_ proposed: CGFloat, viewport: CGSize) -> CGFloat {
        _ = viewport
        return min(max(proposed, scaleRange.lowerBound), scaleRange.upperBound)
    }

    // MARK: - Layout helpers

    private func resolvedPosition(for task: FamilyTask, viewport: CGSize) -> CGPoint {
        if let point = positions[task.id] {
            return point
        }
        return placementPointAvoidingOverlap(near: boardPointAtViewportCenter(viewport: viewport))
    }

    /// 当前视口中心对应的白板坐标（已计入缩放与平移）。
    private func boardPointAtViewportCenter(viewport: CGSize) -> CGPoint {
        let vp = viewport.width > 1 && viewport.height > 1 ? viewport : viewportSize
        guard vp.width > 1, vp.height > 1 else {
            return CGPoint(x: boardSize.width / 2, y: boardSize.height / 2)
        }
        // Duo 半开：优先落到折痕更大的半区中心，避免便签压在 division 上。
        let focusViewport = DuoLayoutSupport.largerHalfRect(
            in: CGRect(origin: .zero, size: vp),
            avoiding: divisionFrame
        )
        let focus = CGPoint(x: focusViewport.midX, y: focusViewport.midY)
        let safeScale = max(scale, 0.01)
        return clampPoint(
            CGPoint(
                x: (focus.x - vp.width / 2) / safeScale + boardSize.width / 2 - boardOffset.width / safeScale,
                y: (focus.y - vp.height / 2) / safeScale + boardSize.height / 2 - boardOffset.height / safeScale
            )
        )
    }

    /// 新便签落在偏好点附近，沿螺旋探测直到不与已有便签重叠。
    private func placementPointAvoidingOverlap(near preferred: CGPoint) -> CGPoint {
        let occupied = Array(positions.values)
        let start = clampPoint(preferred)
        if occupied.contains(where: { notesOverlap(start, $0) }) == false {
            return start
        }

        let step = max(BoardMetrics.tileStride * 0.55, noteSize.width * 0.45)
        for ring in 1...28 {
            let samples = max(ring * 8, 8)
            let radius = step * CGFloat(ring)
            for sample in 0..<samples {
                let angle = (Double(sample) / Double(samples)) * 2 * Double.pi
                let candidate = clampPoint(
                    CGPoint(
                        x: preferred.x + CGFloat(cos(angle)) * radius,
                        y: preferred.y + CGFloat(sin(angle)) * radius
                    )
                )
                if occupied.contains(where: { notesOverlap(candidate, $0) }) == false {
                    return candidate
                }
            }
        }
        return start
    }

    private func notesOverlap(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let gap = BoardMetrics.noteGap * 0.35
        let ax = CGRect(
            x: a.x - noteSize.width / 2,
            y: a.y - noteSize.height / 2,
            width: noteSize.width,
            height: noteSize.height
        ).insetBy(dx: -gap, dy: -gap)
        let bx = CGRect(
            x: b.x - noteSize.width / 2,
            y: b.y - noteSize.height / 2,
            width: noteSize.width,
            height: noteSize.height
        )
        return ax.intersects(bx)
    }

    private func ensurePositions(for tasks: [FamilyTask], viewport: CGSize) {
        let unpositioned = tasks.filter { positions[$0.id] == nil }
        guard unpositioned.isEmpty == false else { return }
        let preferred = boardPointAtViewportCenter(viewport: viewport)
        for task in unpositioned {
            positions[task.id] = placementPointAvoidingOverlap(near: preferred)
            bringToFront(task.id)
        }
        savePositions()
        expandBoardIfNeeded(viewport: viewport.width > 1 ? viewport : viewportSize)
    }

    private func prunePositions(keeping ids: Set<UUID>) {
        let before = positions.count
        positions = positions.filter { ids.contains($0.key) }
        if positions.count != before { savePositions() }
    }

    private func expandBoardIfNeeded(viewport: CGSize) {
        let padding = BoardMetrics.edgePadding
        let maxX = positions.values.map(\.x).max() ?? (BoardMetrics.sideLength / 2)
        let maxY = positions.values.map(\.y).max() ?? (BoardMetrics.sideLength / 2)
        // 保持正方形；默认可铺 100 张，仅在内容超出时等比放大。
        let minFillScale = scaleRange.lowerBound
        let contentExtent = max(
            maxX + noteSize.width / 2 + padding,
            maxY + noteSize.height / 2 + padding,
            BoardMetrics.sideLength,
            viewport.width / minFillScale,
            viewport.height / minFillScale
        )
        let side = ceil(contentExtent / 100) * 100
        if side > boardSize.width || side > boardSize.height {
            boardSize = CGSize(width: side, height: side)
        }
    }

    private func clampPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, noteSize.width / 2 + 8), boardSize.width - noteSize.width / 2 - 8),
            y: min(max(point.y, noteSize.height / 2 + 8), boardSize.height - noteSize.height / 2 - 8)
        )
    }

    // MARK: - Persistence

    private func loadPositions() {
        guard let data = UserDefaults.standard.data(forKey: positionsStorageKey),
              let decoded = try? JSONDecoder().decode([String: CodablePoint].self, from: data)
        else { return }
        positions = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            guard let id = UUID(uuidString: key) else { return nil }
            return (id, CGPoint(x: value.x, y: value.y))
        })
    }

    private func savePositions() {
        let payload = Dictionary(uniqueKeysWithValues: positions.map { id, point in
            (id.uuidString, CodablePoint(x: point.x, y: point.y))
        })
        if let data = try? JSONEncoder().encode(payload) {
            UserDefaults.standard.set(data, forKey: positionsStorageKey)
        }
    }

    private func loadPersistedScale() -> CGFloat? {
        guard let value = UserDefaults.standard.object(forKey: scaleStorageKey) as? Double,
              value.isFinite,
              value > 0
        else { return nil }
        return CGFloat(value)
    }

    private func savePersistedScale(_ value: CGFloat) {
        guard value.isFinite, value > 0 else { return }
        UserDefaults.standard.set(Double(value), forKey: scaleStorageKey)
    }
}

private struct CodablePoint: Codable {
    var x: Double
    var y: Double
}

/// 白板度量：正方形，按 10×10 网格可平铺约 100 张便签。
private enum BoardMetrics {
    static let noteSize = CGSize(width: 148, height: 158)
    static let noteGap: CGFloat = 28
    /// 背景小方格边长（与 Canvas 网格一致）。
    static let gridStep: CGFloat = 28
    /// 自动适配时，内容四周保留的小方格数。
    static let fitEdgeGridCount = 3
    static let edgePadding: CGFloat = 80
    static let gridColumns = 10
    static let capacity = gridColumns * gridColumns

    /// 相邻便签中心距（按较高便签边 + 间距，保证网格接近正方形）。
    static var tileStride: CGFloat {
        max(noteSize.width, noteSize.height) + noteGap
    }

    /// 边长 = 双边距 + 10 张便签短边方向占位 + 9 个间隙。
    static var sideLength: CGFloat {
        edgePadding * 2
            + CGFloat(gridColumns) * max(noteSize.width, noteSize.height)
            + CGFloat(gridColumns - 1) * noteGap
    }

    static var squareSize: CGSize {
        let side = ceil(sideLength / 10) * 10
        return CGSize(width: side, height: side)
    }
}

// MARK: - Corner bins

private struct StickyBoardBookshelf: View {
    let count: Int
    var isHighlighted: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.brown)
                        .frame(width: 44, height: 40)
                        .scaleEffect(isHighlighted ? 1.12 : 1)

                    Text("\(min(count, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .offset(x: 8, y: -6)
                        .opacity(count > 0 ? 1 : 0)
                }

                Text(L10n.Common.completed.localized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.ColorToken.surfaceMuted)
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isHighlighted ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isHighlighted ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Common.completed)
        .accessibilityValue(Text(verbatim: "\(count)"))
    }
}

private struct StickyBoardTrashBin: View {
    let count: Int
    var isHighlighted: Bool = false
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(count > 0 || isHighlighted ? Color.red : Color.secondary)
                        .frame(width: 44, height: 40)
                        .scaleEffect(isHighlighted ? 1.12 : 1)

                    Text("\(min(count, 99))")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 8, y: -6)
                        .opacity(count > 0 ? 1 : 0)
                }

                Text(L10n.Common.overdue.localized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.ColorToken.surfaceMuted)
                    .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isHighlighted ? Color.red.opacity(0.9) : Color.primary.opacity(0.12),
                        lineWidth: isHighlighted ? 2 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Common.overdue)
        .accessibilityValue(Text(verbatim: "\(count)"))
    }
}

// MARK: - Look

private enum StickyNoteCurlStyle: CaseIterable {
    /// 近似平整，仅有轻微浮起阴影
    case flat
    /// 底边轻微掀起
    case softLift
    /// 右下角明显卷起
    case cornerTrailing
    /// 左下角明显卷起
    case cornerLeading
}

private struct StickyNoteLook {
    /// 纸面主色：组织主题色的浅透明变体（彼此仅深浅略有差异）。
    let paper: Color
    let pin: Color
    let curlStyle: StickyNoteCurlStyle
    let rotationDegrees: Double
    let jitter: CGPoint

    /// 纸面贴近 group 主题色；图钉颜色按任务 ID 稳定随机。
    static func stable(for id: UUID, theme: Color) -> StickyNoteLook {
        let seed = id.uuidString.utf8.reduce(0) { $0 &* 31 &+ Int($1) }
        let styles = StickyNoteCurlStyle.allCases
        // 浅透明主题色：保持色系一致，避免纸面过深影响文字。
        let strengths: [Double] = [0.18, 0.22, 0.26, 0.30, 0.20, 0.24]
        let strength = strengths[abs(seed) % strengths.count]
        let pinPalette: [Color] = [
            .red, .orange, .yellow, .green, .mint, .teal,
            .cyan, .blue, .indigo, .purple, .pink, .brown
        ]
        return StickyNoteLook(
            paper: theme.opacity(strength),
            pin: pinPalette[abs(seed / 7) % pinPalette.count],
            curlStyle: styles[abs(seed / 41) % styles.count],
            rotationDegrees: Double((abs(seed / 11) % 11) - 5) * 0.85,
            jitter: CGPoint(
                x: CGFloat((abs(seed / 17) % 17) - 8),
                y: CGFloat((abs(seed / 23) % 15) - 7)
            )
        )
    }

    var curlSize: CGFloat {
        switch curlStyle {
        case .flat: 0
        case .softLift: 14
        case .cornerTrailing, .cornerLeading: 30
        }
    }
}

// MARK: - Note card

private struct TodoStickyNoteCard: View {
    let look: StickyNoteLook
    let title: String
    /// 标题外次要信息，调用方已截断至多 2 条。
    let detailLines: [String]
    let avatars: [TaskCardAvatarSource]
    var hasAttachments: Bool = false
    let isDragging: Bool
    var isPinInserting: Bool = false
    let onActivate: () -> Void
    let onOpen: () -> Void

    /// `false` = 悬在纸面上方（钉入起点）；`true` = 已钉入。
    @State private var pinPlanted = true

    private var curlSize: CGFloat { look.curlSize }
    private var curlCorner: StickyNoteCurlCorner {
        switch look.curlStyle {
        case .cornerLeading: .bottomLeading
        case .flat, .softLift, .cornerTrailing: .bottomTrailing
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            paperCastShadow
                .allowsHitTesting(false)

            ZStack(alignment: .topLeading) {
                StickyNotePaperShape(curlSize: curlSize, corner: curlCorner, softLift: look.curlStyle == .softLift)
                    // 内容区纯平色，光影只走边缘描边。
                    .fill(paperFill)
                    .overlay {
                        StickyNotePaperShape(curlSize: curlSize, corner: curlCorner, softLift: look.curlStyle == .softLift)
                            .stroke(edgeLightingStroke, lineWidth: 2.2)
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        StickyNotePaperShape(curlSize: curlSize, corner: curlCorner, softLift: look.curlStyle == .softLift)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.7)
                    }

                if look.curlStyle != .flat {
                    curlFlap
                }

                noteContent
            }
            .overlay(alignment: .topTrailing) {
                if hasAttachments {
                    Image(systemName: "paperclip")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 10)
                        .padding(.trailing, 10)
                        .accessibilityLabel(L10n.Common.attachments.localized)
                }
            }
            .clipShape(StickyNotePaperShape(curlSize: curlSize, corner: curlCorner, softLift: look.curlStyle == .softLift))

            StickyBoardPushPin(color: look.pin)
                .opacity(isDragging ? 0 : 1)
                .offset(y: pinPlanted ? -8 : -18)
                .scaleEffect(pinPlanted ? 1 : 1.28)
                .allowsHitTesting(false)
        }
        .shadow(
            color: .black.opacity(isDragging ? 0.16 : 0.08),
            radius: isDragging ? 10 : 5,
            x: 1,
            y: isDragging ? 6 : 3
        )
        .contentShape(StickyNotePaperShape(curlSize: curlSize, corner: curlCorner, softLift: look.curlStyle == .softLift))
        .onTapGesture {
            onActivate()
            onOpen()
        }
        .onChange(of: isDragging) { _, dragging in
            if dragging {
                pinPlanted = false
            }
        }
        .onChange(of: isPinInserting) { _, inserting in
            guard inserting else { return }
            pinPlanted = false
            withAnimation(.easeIn(duration: 0.2)) {
                pinPlanted = true
            }
        }
    }

    /// 内容区域无渐变光影，避免文字被染色/压暗。
    private var paperFill: Color {
        Color(.secondarySystemGroupedBackground)
    }

    /// 仅贴合纸缘的高光 + 主题色 + 阴影，不进入内容区。
    private var edgeLightingStroke: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.34),
                look.paper.opacity(0.85),
                Color.black.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var paperCastShadow: some View {
        switch look.curlStyle {
        case .flat:
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.06))
                .blur(radius: 3)
                .offset(x: 1.5, y: 3)
                .padding(2)
        case .softLift:
            Ellipse()
                .fill(Color.black.opacity(0.08))
                .frame(width: 110, height: 12)
                .blur(radius: 4)
                .offset(y: 76)
        case .cornerTrailing:
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 40, height: 12)
                .blur(radius: 2.5)
                .offset(x: 44, y: 70)
            Ellipse()
                .fill(Color.black.opacity(0.05))
                .frame(width: 100, height: 10)
                .blur(radius: 5)
                .offset(x: 6, y: 74)
        case .cornerLeading:
            Ellipse()
                .fill(Color.black.opacity(0.10))
                .frame(width: 40, height: 12)
                .blur(radius: 2.5)
                .offset(x: -44, y: 70)
            Ellipse()
                .fill(Color.black.opacity(0.05))
                .frame(width: 100, height: 10)
                .blur(radius: 5)
                .offset(x: -6, y: 74)
        }
    }

    @ViewBuilder
    private var curlFlap: some View {
        let size = max(curlSize, 12)
        StickyNoteCurlFlap(curlSize: size, corner: curlCorner)
            .fill(
                LinearGradient(
                    colors: curlFlapColors,
                    startPoint: curlCorner == .bottomTrailing ? .topLeading : .topTrailing,
                    endPoint: curlCorner == .bottomTrailing ? .bottomTrailing : .bottomLeading
                )
            )
            .overlay {
                StickyNoteCurlFlap(curlSize: size, corner: curlCorner)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.6)
            }
            .shadow(
                color: .black.opacity(0.08),
                radius: 1,
                x: curlCorner == .bottomTrailing ? -1 : 1,
                y: 0.5
            )
    }

    private var curlFlapColors: [Color] {
        [
            Color(.secondarySystemGroupedBackground),
            look.paper.opacity(0.55),
            Color.primary.opacity(0.04)
        ]
    }

    private var noteContent: some View {
        let secondary = Array(detailLines.prefix(2))
        let titleLineLimit = max(5 - secondary.count, 2)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if avatars.isEmpty == false {
                    TaskCardForWhomTrailing(
                        sources: avatars,
                        style: .compact,
                        showsEmptyPlaceholder: false,
                        accentColor: look.pin
                    )
                }
                Spacer(minLength: 0)
                // 右上角留给附件图标（overlay）。
                if hasAttachments {
                    Color.clear.frame(width: 14, height: 14)
                }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            ForEach(Array(secondary.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.trailing, curlCorner == .bottomTrailing ? curlSize * 0.55 : 0)
            .padding(.leading, curlCorner == .bottomLeading ? curlSize * 0.55 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }
}

private enum StickyNoteCurlCorner {
    case bottomTrailing
    case bottomLeading
}

private struct StickyNotePaperShape: Shape {
    var curlSize: CGFloat
    var corner: StickyNoteCurlCorner
    var softLift: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lift = softLift ? max(curlSize, 10) : curlSize

        path.move(to: CGPoint(x: rect.minX + 3, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - 3, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + 3),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )

        if lift <= 0.5 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - 3, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - 3),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        } else if softLift {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lift * 0.35))
            path.addQuadCurve(
                to: CGPoint(x: rect.midX, y: rect.maxY),
                control: CGPoint(x: rect.maxX - lift * 0.2, y: rect.maxY + lift * 0.15)
            )
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - lift * 0.35),
                control: CGPoint(x: rect.minX + lift * 0.2, y: rect.maxY + lift * 0.15)
            )
        } else if corner == .bottomTrailing {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lift))
            path.addLine(to: CGPoint(x: rect.maxX - lift, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + 3, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - 3),
                control: CGPoint(x: rect.minX, y: rect.maxY)
            )
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - 3))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX - 3, y: rect.maxY),
                control: CGPoint(x: rect.maxX, y: rect.maxY)
            )
            path.addLine(to: CGPoint(x: rect.minX + lift, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lift))
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 3))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 3, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

private struct StickyNoteCurlFlap: Shape {
    var curlSize: CGFloat
    var corner: StickyNoteCurlCorner

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch corner {
        case .bottomTrailing:
            let origin = CGPoint(x: rect.maxX - curlSize, y: rect.maxY - curlSize)
            path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - curlSize))
            path.addLine(to: CGPoint(x: rect.maxX - curlSize, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.maxY - curlSize),
                control: CGPoint(x: origin.x + curlSize * 0.35, y: origin.y + curlSize * 0.18)
            )
        case .bottomLeading:
            let origin = CGPoint(x: rect.minX + curlSize, y: rect.maxY - curlSize)
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY - curlSize))
            path.addLine(to: CGPoint(x: rect.minX + curlSize, y: rect.maxY))
            path.addQuadCurve(
                to: CGPoint(x: rect.minX, y: rect.maxY - curlSize),
                control: CGPoint(x: origin.x - curlSize * 0.35, y: origin.y + curlSize * 0.18)
            )
        }
        path.closeSubpath()
        return path
    }
}

private struct StickyBoardPushPin: View {
    let color: Color

    var body: some View {
        ZStack {
            // 针脚投在纸面上的阴影
            Ellipse()
                .fill(Color.black.opacity(0.28))
                .frame(width: 9, height: 3.5)
                .blur(radius: 0.6)
                .offset(x: 1.2, y: 7.5)

            // 金属针
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.95), Color.primary.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 1.5, height: 8)
                .offset(y: 4)

            // 针头圆盘
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.2))
                    .frame(width: 13, height: 13)
                    .offset(y: 0.6)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.75),
                                color,
                                color.opacity(0.72)
                            ],
                            center: UnitPoint(x: 0.32, y: 0.28),
                            startRadius: 0.6,
                            endRadius: 8
                        )
                    )
                    .frame(width: 12, height: 12)
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 0.6)
                    }

                // 针头高光
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 4.5, height: 2.2)
                    .offset(x: -2, y: -2.2)
            }
            .offset(y: -0.5)
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    TodoStickyBoardView(
        nearTasks: [],
        farTasks: [],
        overdueCount: 2,
        completedCount: 5,
        displayTitle: { _ in "Buy milk and bread for breakfast" },
        forWhomAvatars: { _ in [] },
        detailLines: { _ in ["Due today", "Corner grocery"] },
        hasAttachments: { _ in true },
        isCompletionChecked: { _ in false },
        isFlying: { _ in false },
        isInteractionLocked: { _ in false },
        onToggleComplete: { _ in },
        onOpen: { _ in },
        onOpenOverdueBin: {},
        onOpenCompletedArchive: {},
        onDropComplete: { _ in },
        onDropDelete: { _ in }
    )
    .environmentObject(AppSettingsManager.shared)
}
#endif
