import UIKit
import WebKit

struct ExportOptions {
    var format: ExportFormat
    var paper: Paper
    var margins: Margins
    var pageNumbers: Bool
    var headingPageBreak: Bool
    var tableOfContents: Bool
    var title: String
    var fileName: String
    var htmlFollowsDarkMode: Bool
}

enum ExportError: LocalizedError {
    case noPages
    var errorDescription: String? { "The document produced no pages." }
}

/// Turns the rendered preview into a PDF or a self-contained HTML file.
@MainActor
enum Exporter {
    /// Writes the export into a temporary folder and returns the file's URL, ready to share.
    static func export(from preview: PreviewController, options: ExportOptions) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(options.fileName)
        switch options.format {
        case .pdf:
            let data = try makePDF(from: preview.webView, options: options)
            try data.write(to: url)
        case .html:
            let parts = await preview.exportParts()
            let body = AssetSchemeHandler.inlinePictures(in: parts.body, base: preview.baseFolder)
            let html = makeHTML(body: body, mathCSS: parts.mathCSS, options: options)
            try Data(html.utf8).write(to: url)
        }
        return url
    }

    // MARK: PDF

    static func makePDF(from webView: WKWebView, options: ExportOptions) throws -> Data {
        let renderer = NumberedPageRenderer()
        renderer.showsPageNumbers = options.pageNumbers
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)

        let paperRect = CGRect(origin: .zero, size: options.paper.size)
        let m = options.margins.points
        let printable = paperRect.insetBy(dx: m, dy: m)
        renderer.setValue(NSValue(cgRect: paperRect), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: printable), forKey: "printableRect")

        let data = NSMutableData()
        let info: [String: Any] = [
            kCGPDFContextTitle as String: options.title,
            kCGPDFContextCreator as String: "Mappledown"
        ]
        UIGraphicsBeginPDFContextToData(data, paperRect, info)
        let pages = renderer.numberOfPages
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: pages))
        for page in 0..<pages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        if pages == 0 { throw ExportError.noPages }
        return data as Data
    }

    // MARK: HTML

    static func makeHTML(body: String, mathCSS: String, options: ExportOptions) -> String {
        func resource(_ name: String, _ ext: String, _ dir: String = "Web") -> String {
            guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: dir),
                  let s = try? String(contentsOf: url, encoding: .utf8) else { return "" }
            return s
        }
        let baseCSS = resource("preview", "css")
        let lightCode = resource("hljs-light.min", "css", "Web/vendor")
        let darkCode = resource("hljs-dark.min", "css", "Web/vendor")
        var css = baseCSS + "\n" + lightCode + "\n" + mathCSS
        if options.htmlFollowsDarkMode {
            css += """

            @media (prefers-color-scheme: dark) {
              :root { --bg: #000000; --text: #F2F2F7; --text2: #AEAEB2; --sep: #38383A; --code-bg: #1C1C1E; --accent: #A5A6F6; --error: #FF6961; }
              \(darkCode)
            }
            """
        }
        let title = options.title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="generator" content="Mappledown">
        <title>\(title)</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }
}

/// Draws a centered page number at the foot of each PDF page.
final class NumberedPageRenderer: UIPrintPageRenderer {
    var showsPageNumbers = true

    override func drawPage(at pageIndex: Int, in printableRect: CGRect) {
        super.drawPage(at: pageIndex, in: printableRect)
        guard showsPageNumbers else { return }
        let paper = paperRect
        let text = "\(pageIndex + 1)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray
        ]
        let size = text.size(withAttributes: attrs)
        let bottomMargin = paper.maxY - self.printableRect.maxY
        let y = paper.maxY - bottomMargin / 2 - size.height / 2
        text.draw(at: CGPoint(x: paper.midX - size.width / 2, y: y), withAttributes: attrs)
    }
}
