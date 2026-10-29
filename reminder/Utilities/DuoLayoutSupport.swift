import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// iPhone Duo / 可缩放窗口布局辅助。
///
/// - 日常构建（iOS 26 SDK）：用尺寸与 size class 做宽屏分栏、可读列宽、安全区。
/// - 在 **Xcode 27.1+** 构建时于 target 增加 `IPHONE_DUO_SDK`（Swift Active Compilation Conditions），
///   以启用 `reservedRegions` 折痕/遮挡几何（见文件末尾条件编译块）。
enum DuoLayoutSupport {
    /// 表单 / 设置类内容在超宽窗口中的最大可读宽度。
    static let readableContentMaxWidth: CGFloat = 720

    /// 判定为「扩展画布」：regular 宽度，或接近方屏/宽屏（内屏展开常见形态）。
    static func prefersExpandedLayout(
        size: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        if horizontalSizeClass == .regular { return true }
        guard size.width > 1, size.height > 1 else { return false }
        return size.width >= 700 || (size.width / size.height) >= 0.85
    }

    /// 是否适合双栏（列表 + 详情）。
    static func prefersSplitNavigation(
        size: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> Bool {
        if horizontalSizeClass == .regular { return true }
        return size.width >= 900
    }

    /// 在避开折痕/遮挡带后，取面积更大的半区（放置主控件）。
    static func largerHalfRect(in bounds: CGRect, avoiding reserved: CGRect?) -> CGRect {
        guard let reserved, reserved.isNull == false, reserved.width > 1, reserved.height > 1 else {
            return bounds
        }
        let clipped = reserved.intersection(bounds)
        guard clipped.isNull == false, clipped.width > 1, clipped.height > 1 else {
            return bounds
        }

        if clipped.height >= bounds.height * 0.55 {
            // 竖直折痕：左右两半
            let left = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: max(clipped.minX - bounds.minX, 0),
                height: bounds.height
            )
            let right = CGRect(
                x: clipped.maxX,
                y: bounds.minY,
                width: max(bounds.maxX - clipped.maxX, 0),
                height: bounds.height
            )
            return left.width >= right.width ? left : right
        }

        if clipped.width >= bounds.width * 0.55 {
            // 水平折痕：上下两半
            let top = CGRect(
                x: bounds.minX,
                y: bounds.minY,
                width: bounds.width,
                height: max(clipped.minY - bounds.minY, 0)
            )
            let bottom = CGRect(
                x: bounds.minX,
                y: clipped.maxY,
                width: bounds.width,
                height: max(bounds.maxY - clipped.maxY, 0)
            )
            return top.height >= bottom.height ? top : bottom
        }

        return bounds
    }

    /// 为避开折痕带增加的内容边距（折痕两侧各留 gutter）。
    static func contentInsets(
        avoiding reserved: CGRect?,
        in size: CGSize,
        gutter: CGFloat = 12
    ) -> EdgeInsets {
        guard let reserved, size.width > 1, size.height > 1 else {
            return EdgeInsets()
        }
        let bounds = CGRect(origin: .zero, size: size)
        let clipped = reserved.intersection(bounds)
        guard clipped.isNull == false, clipped.width > 1, clipped.height > 1 else {
            return EdgeInsets()
        }

        if clipped.height >= size.height * 0.55 {
            return EdgeInsets(
                top: 0,
                leading: max(0, clipped.maxX <= size.width * 0.5 ? 0 : gutter),
                bottom: 0,
                trailing: max(0, clipped.minX >= size.width * 0.5 ? 0 : gutter)
            )
        }
        if clipped.width >= size.width * 0.55 {
            return EdgeInsets(
                top: max(0, clipped.maxY <= size.height * 0.5 ? 0 : gutter),
                leading: 0,
                bottom: max(0, clipped.minY >= size.height * 0.5 ? 0 : gutter),
                trailing: 0
            )
        }
        return EdgeInsets()
    }
}

// MARK: - Geometry metrics

struct DuoLayoutMetrics: Equatable {
    var size: CGSize = .zero
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    var horizontalSizeClass: UserInterfaceSizeClass?
    /// 活动折痕（书本/笔记本半开）；无 SDK 支持时为 `nil`。
    var divisionFrame: CGRect?
    /// 摄像头等遮挡区。
    var occlusionFrame: CGRect?

    var prefersExpandedLayout: Bool {
        DuoLayoutSupport.prefersExpandedLayout(
            size: size,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    var prefersSplitNavigation: Bool {
        DuoLayoutSupport.prefersSplitNavigation(
            size: size,
            horizontalSizeClass: horizontalSizeClass
        )
    }

    /// 折痕沿竖直方向（左右分栏）。
    var isVerticalDivision: Bool {
        guard let divisionFrame, size.height > 1 else { return false }
        return divisionFrame.height >= size.height * 0.6
    }

    /// 折痕沿水平方向（上下分栏）。
    var isHorizontalDivision: Bool {
        guard let divisionFrame, size.width > 1 else { return false }
        return divisionFrame.width >= size.width * 0.6
    }

    /// 避开折痕后面积更大的半区（视口坐标）。
    var largerContentRect: CGRect {
        DuoLayoutSupport.largerHalfRect(
            in: CGRect(origin: .zero, size: size),
            avoiding: divisionFrame
        )
    }

    /// 为控件增加的折痕避让边距。
    var divisionAvoidanceInsets: EdgeInsets {
        DuoLayoutSupport.contentInsets(avoiding: divisionFrame, in: size)
    }

    var hasActiveDivision: Bool {
        guard let divisionFrame else { return false }
        return divisionFrame.width > 1 && divisionFrame.height > 1
    }
}

extension GeometryProxy {
    /// 汇总 Duo / 可缩放窗口指标（含可选 reservedRegions）。
    func duoLayoutMetrics(
        horizontalSizeClass: UserInterfaceSizeClass?
    ) -> DuoLayoutMetrics {
        DuoLayoutMetrics(
            size: size,
            safeAreaInsets: safeAreaInsets,
            horizontalSizeClass: horizontalSizeClass,
            divisionFrame: duoDivisionFrame,
            occlusionFrame: duoOcclusionFrame
        )
    }

    var duoDivisionFrame: CGRect? {
        #if IPHONE_DUO_SDK
        duoReservedFrame(kind: .division)
        #else
        nil
        #endif
    }

    var duoOcclusionFrame: CGRect? {
        #if IPHONE_DUO_SDK
        duoReservedFrame(kind: .occlusion)
        #else
        nil
        #endif
    }
}

// MARK: - View modifiers

/// 根 Tab 注入：宽屏 / Duo 内屏时为 `true`。
private struct DuoPrefersExpandedChromeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var duoPrefersExpandedChrome: Bool {
        get { self[DuoPrefersExpandedChromeKey.self] }
        set { self[DuoPrefersExpandedChromeKey.self] = newValue }
    }
}

extension View {
    /// 宽屏下限制内容最大宽度并居中（表单、设置列表等）。
    func duoReadableContentWidth(
        _ maxWidth: CGFloat = DuoLayoutSupport.readableContentMaxWidth
    ) -> some View {
        modifier(DuoReadableContentWidthModifier(maxWidth: maxWidth))
    }

    /// 画布类页面：随安全区（含侧栏 Tab）内缩，避免压住系统 chrome。
    func duoCanvasChromePadding(
        extra: EdgeInsets = EdgeInsets()
    ) -> some View {
        modifier(DuoCanvasChromePaddingModifier(extra: extra))
    }
}

private struct DuoReadableContentWidthModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        // 窄屏上 maxWidth 大于容器时仍由父级约束；宽屏则居中可读列。
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct DuoCanvasChromePaddingModifier: ViewModifier {
    let extra: EdgeInsets

    func body(content: Content) -> some View {
        content
            .safeAreaPadding(.leading, extra.leading)
            .safeAreaPadding(.trailing, extra.trailing)
            .safeAreaPadding(.top, extra.top)
            .safeAreaPadding(.bottom, extra.bottom)
    }
}

// MARK: - iOS 27.1+ reservedRegions（需 IPHONE_DUO_SDK）

#if IPHONE_DUO_SDK
import SwiftUI

private extension GeometryProxy {
    enum DuoReservedKind {
        case division
        case occlusion
    }

    func duoReservedFrame(kind: DuoReservedKind) -> CGRect? {
        // API: GeometryProxy.reservedRegions(kind:) — iOS 27.1+
        // 签名以本机 27.1 SDK 为准；若编译报错请对照 Apple 文档微调。
        let regions: [ReservedRegion]
        switch kind {
        case .division:
            regions = Array(reservedRegions(kind: .division))
        case .occlusion:
            regions = Array(reservedRegions(kind: .occlusion))
        }
        return regions.first?.rect
    }
}
#endif
