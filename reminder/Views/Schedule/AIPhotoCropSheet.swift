import SwiftUI
import UIKit

struct AIPhotoCropPendingContext: Identifiable {
    let id = UUID()
    let image: UIImage
    let source: AIPhotoTaskCreationLogger.CaptureSource
}

/// 归一化四边形选区（原图坐标系，左上为 (0,0)）。
struct NormalizedCropQuad: Equatable, Sendable {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint

    static func defaultCentered(relativeSize: CGFloat = 0.45) -> NormalizedCropQuad {
        let inset = (1 - relativeSize) / 2
        return NormalizedCropQuad(
            topLeft: CGPoint(x: inset, y: inset),
            topRight: CGPoint(x: 1 - inset, y: inset),
            bottomLeft: CGPoint(x: inset, y: 1 - inset),
            bottomRight: CGPoint(x: 1 - inset, y: 1 - inset)
        )
    }

    var isApproximatelyAxisAligned: Bool {
        let tolerance: CGFloat = 0.02
        return abs(topLeft.y - topRight.y) < tolerance
            && abs(bottomLeft.y - bottomRight.y) < tolerance
            && abs(topLeft.x - bottomLeft.x) < tolerance
            && abs(topRight.x - bottomRight.x) < tolerance
    }

    func point(for corner: CropCorner) -> CGPoint {
        switch corner {
        case .topLeft: topLeft
        case .topRight: topRight
        case .bottomLeft: bottomLeft
        case .bottomRight: bottomRight
        }
    }

    mutating func set(_ corner: CropCorner, to point: CGPoint) {
        switch corner {
        case .topLeft: topLeft = point
        case .topRight: topRight = point
        case .bottomLeft: bottomLeft = point
        case .bottomRight: bottomRight = point
        }
    }

    var isValidRegion: Bool {
        polygonArea(topLeft, topRight, bottomRight, bottomLeft) > 0.01
    }

    /// Edge Function `recognition_region` 请求体。
    var apiPayload: RecognitionRegionPayload {
        RecognitionRegionPayload(quad: self)
    }
}

struct RecognitionRegionPayload: Encodable, Sendable {
    struct Point: Encodable, Sendable {
        let x: Double
        let y: Double
    }

    let topLeft: Point
    let topRight: Point
    let bottomLeft: Point
    let bottomRight: Point

    enum CodingKeys: String, CodingKey {
        case topLeft = "top_left"
        case topRight = "top_right"
        case bottomLeft = "bottom_left"
        case bottomRight = "bottom_right"
    }

    init(quad: NormalizedCropQuad) {
        topLeft = Point(x: Double(quad.topLeft.x), y: Double(quad.topLeft.y))
        topRight = Point(x: Double(quad.topRight.x), y: Double(quad.topRight.y))
        bottomLeft = Point(x: Double(quad.bottomLeft.x), y: Double(quad.bottomLeft.y))
        bottomRight = Point(x: Double(quad.bottomRight.x), y: Double(quad.bottomRight.y))
    }
}

extension NormalizedCropQuad {
    var isValidForCrop: Bool { isValidRegion }
}

enum CropCorner: CaseIterable, Identifiable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: Self { self }
}

/// 拍照后在原图上用红框标记识别区域（不裁剪原图），再提交 AI 识图。
struct AIPhotoCropSheet: View {
    let image: UIImage
    let onConfirm: (_ quad: NormalizedCropQuad) -> Void
    let onRetake: () -> Void

    @State private var cropQuad = NormalizedCropQuad.defaultCentered()
    @State private var draggingCorner: CropCorner?
    @State private var dragStartPoint: CGPoint?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let layout = ImageCropLayout(image: image, containerSize: geometry.size)

                ZStack(alignment: .topLeading) {
                    Color.black

                    if let imageRect = layout.imageRect {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageRect.width, height: imageRect.height)
                            .offset(x: imageRect.minX, y: imageRect.minY)

                        cropDimming(imageRect: imageRect)
                            .allowsHitTesting(false)

                        cropQuadOutline(imageRect: imageRect)
                            .allowsHitTesting(false)

                        ForEach(CropCorner.allCases) { corner in
                            cornerHandle(corner: corner, imageRect: imageRect)
                        }
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .coordinateSpace(name: "cropSpace")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("用红框标记识别区域")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重拍", action: onRetake)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("识别此区域", action: confirmSelection)
                        .fontWeight(.semibold)
                        .disabled(cropQuad.isValidRegion == false)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActions
            }
        }
        .preferredColorScheme(.dark)
    }

    private var bottomActions: some View {
        HStack(spacing: 12) {
            Button("重拍", action: onRetake)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            Button(action: confirmSelection) {
                Text("识别此区域")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(.black)
            }
            .disabled(cropQuad.isValidRegion == false)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color.black.opacity(0.85))
    }

    private func confirmSelection() {
        guard cropQuad.isValidRegion else { return }
        onConfirm(cropQuad)
    }

    private func cropDimming(imageRect: CGRect) -> some View {
        let corners = pixelCorners(in: imageRect)

        return Path { path in
            path.addRect(CGRect(origin: .zero, size: imageRect.size))
            path.move(to: corners.topLeft)
            path.addLine(to: corners.topRight)
            path.addLine(to: corners.bottomRight)
            path.addLine(to: corners.bottomLeft)
            path.closeSubpath()
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .frame(width: imageRect.width, height: imageRect.height)
        .offset(x: imageRect.minX, y: imageRect.minY)
    }

    private func cropQuadOutline(imageRect: CGRect) -> some View {
        let corners = pixelCorners(in: imageRect)

        return ZStack {
            Path { path in
                path.move(to: corners.topLeft)
                path.addLine(to: corners.topRight)
                path.addLine(to: corners.bottomRight)
                path.addLine(to: corners.bottomLeft)
                path.closeSubpath()
            }
            .fill(Color.red.opacity(0.10))

            Path { path in
                path.move(to: corners.topLeft)
                path.addLine(to: corners.topRight)
                path.addLine(to: corners.bottomRight)
                path.addLine(to: corners.bottomLeft)
                path.closeSubpath()
            }
            .stroke(Color.red, lineWidth: 3)
        }
        .frame(width: imageRect.width, height: imageRect.height)
        .offset(x: imageRect.minX, y: imageRect.minY)
    }

    private func cornerHandle(corner: CropCorner, imageRect: CGRect) -> some View {
        let point = viewPoint(for: corner, in: imageRect)

        return Circle()
            .fill(Color.red)
            .frame(width: 28, height: 28)
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .overlay {
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
            }
            .position(x: point.x, y: point.y)
            .gesture(cornerDragGesture(corner: corner, imageRect: imageRect))
            .accessibilityLabel(cornerAccessibilityLabel(corner))
    }

    private func cornerAccessibilityLabel(_ corner: CropCorner) -> String {
        switch corner {
        case .topLeft: "左上角控制点"
        case .topRight: "右上角控制点"
        case .bottomLeft: "左下角控制点"
        case .bottomRight: "右下角控制点"
        }
    }

    private func cornerDragGesture(corner: CropCorner, imageRect: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("cropSpace"))
            .onChanged { value in
                if draggingCorner != corner {
                    draggingCorner = corner
                    dragStartPoint = cropQuad.point(for: corner)
                }
                guard let start = dragStartPoint else { return }

                let deltaX = value.translation.width / imageRect.width
                let deltaY = value.translation.height / imageRect.height
                let next = clampNormalized(
                    CGPoint(x: start.x + deltaX, y: start.y + deltaY)
                )
                cropQuad.set(corner, to: next)
            }
            .onEnded { _ in
                draggingCorner = nil
                dragStartPoint = nil
            }
    }

    private struct PixelCorners {
        let topLeft: CGPoint
        let topRight: CGPoint
        let bottomLeft: CGPoint
        let bottomRight: CGPoint
    }

    private func pixelCorners(in imageRect: CGRect) -> PixelCorners {
        func localPoint(_ normalized: CGPoint) -> CGPoint {
            CGPoint(
                x: normalized.x * imageRect.width,
                y: normalized.y * imageRect.height
            )
        }

        return PixelCorners(
            topLeft: localPoint(cropQuad.topLeft),
            topRight: localPoint(cropQuad.topRight),
            bottomLeft: localPoint(cropQuad.bottomLeft),
            bottomRight: localPoint(cropQuad.bottomRight)
        )
    }

    private func viewPoint(for corner: CropCorner, in imageRect: CGRect) -> CGPoint {
        let normalized = cropQuad.point(for: corner)
        return CGPoint(
            x: imageRect.minX + normalized.x * imageRect.width,
            y: imageRect.minY + normalized.y * imageRect.height
        )
    }

    private func clampNormalized(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), 1),
            y: min(max(point.y, 0), 1)
        )
    }
}

private func polygonArea(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
    abs(
        (a.x * b.y - b.x * a.y)
            + (b.x * c.y - c.x * b.y)
            + (c.x * d.y - d.x * c.y)
            + (d.x * a.y - a.x * d.y)
    ) / 2
}

private struct ImageCropLayout {
    let imageRect: CGRect?

    init(image: UIImage, containerSize: CGSize) {
        guard containerSize.width > 0, containerSize.height > 0 else {
            imageRect = nil
            return
        }

        let pixelSize = image.orientedPixelSize
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            imageRect = nil
            return
        }

        let scale = min(containerSize.width / pixelSize.width, containerSize.height / pixelSize.height)
        let fitted = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        imageRect = CGRect(
            x: (containerSize.width - fitted.width) / 2,
            y: (containerSize.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}

extension UIImage {
    /// 显示用像素尺寸（考虑 EXIF 方向）。
    var orientedPixelSize: CGSize {
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: size.height, height: size.width)
        default:
            return CGSize(width: size.width, height: size.height)
        }
    }
}
