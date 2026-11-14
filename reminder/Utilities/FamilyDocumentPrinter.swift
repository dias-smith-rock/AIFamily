import SwiftUI
import UIKit

/// 用系统打印面板直接打印一份纯文本文档（日程、待办、清单）。
enum FamilyDocumentPrinter {
    struct Section: Sendable {
        var heading: String
        var lines: [String]
    }

    @MainActor
    static func printImages(jobName: String, images: [UIImage]) {
        let pages = images.isEmpty ? [UIImage()] : images
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        info.outputType = .general
        info.orientation = .portrait
        controller.printInfo = info
        controller.printFormatter = nil
        controller.printPageRenderer = ScheduleImagePrintRenderer(images: pages)
        present(controller)
    }

    @MainActor
    static func printDocument(jobName: String, title: String, sections: [Section]) {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = jobName
        info.outputType = .general
        controller.printInfo = info

        let formatter = UIMarkupTextPrintFormatter(markupText: markup(title: title, sections: sections))
        formatter.perPageContentInsets = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        controller.printFormatter = formatter
        present(controller)
    }

    @MainActor
    private static func present(_ controller: UIPrintInteractionController) {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            controller.present(animated: true, completionHandler: nil)
            return
        }
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        guard let view = window?.rootViewController?.view else {
            controller.present(animated: true, completionHandler: nil)
            return
        }
        let anchor = CGRect(x: view.bounds.midX, y: view.safeAreaInsets.top + 8, width: 1, height: 1)
        controller.present(from: anchor, in: view, animated: true, completionHandler: nil)
    }

    private static func markup(title: String, sections: [Section]) -> String {
        var html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 12pt; color: #111; }
        h1 { font-size: 20pt; margin: 0 0 8pt; }
        h2 { font-size: 13pt; margin: 16pt 0 4pt; border-bottom: 0.4pt solid #bbb; padding-bottom: 2pt; }
        p { margin: 3pt 0; }
        </style></head><body><h1>\(escape(title))</h1>
        """
        let printed = sections.isEmpty
            ? [Section(heading: "", lines: [])]
            : sections
        for section in printed {
            if section.heading.isEmpty == false {
                html += "<h2>\(escape(section.heading))</h2>"
            }
            let lines = section.lines.isEmpty ? ["—"] : section.lines
            for line in lines {
                html += "<p>\(escape(line))</p>"
            }
        }
        html += "</body></html>"
        return html
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

final class ScheduleImagePrintRenderer: UIPrintPageRenderer {
    private let images: [UIImage]

    init(images: [UIImage]) {
        self.images = images
        super.init()
    }

    override var numberOfPages: Int { images.count }

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        guard images.indices.contains(pageIndex) else { return }
        let image = images[pageIndex]
        guard image.size.width > 1, image.size.height > 1 else { return }
        let fitted = Self.aspectFit(image.size, in: printableRect)
        image.draw(in: fitted)
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let width = size.width * scale
        let height = size.height * scale
        return CGRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

struct FamilyPrintToolbarButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "printer")
                .font(.system(size: 17, weight: .semibold))
        }
        .accessibilityLabel(L10n.Common.print)
    }
}
