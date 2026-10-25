import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves pictures stored next to the open .md file to the preview page.
/// The page asks for mdasset://doc/?p=<relative path> (or mdasset://abs/?p=<absolute path>).
@MainActor
final class AssetSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdasset"
    var baseFolder: URL?

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url,
              let file = AssetSchemeHandler.fileURL(for: url, base: baseFolder),
              let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Turns an mdasset:// URL into the file it names.
    nonisolated static func fileURL(for url: URL, base: URL?) -> URL? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "p" })?.value, !path.isEmpty else { return nil }
        switch comps.host {
        case "doc":
            guard let base else { return nil }
            return URL(fileURLWithPath: path, relativeTo: base).standardizedFileURL
        case "abs":
            return URL(fileURLWithPath: path).standardizedFileURL
        default:
            return nil
        }
    }

    /// Replaces mdasset:// picture links in exported HTML with the pictures themselves (data: URLs).
    nonisolated static func inlinePictures(in html: String, base: URL?) -> String {
        guard let re = try? NSRegularExpression(pattern: "mdasset://[a-z]+/\\?p=[^\"'\\s)>]+") else { return html }
        var result = html
        let ns = html as NSString
        for match in re.matches(in: html, range: NSRange(location: 0, length: ns.length)).reversed() {
            let link = ns.substring(with: match.range).replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: link), let file = fileURL(for: url, base: base),
                  let data = try? Data(contentsOf: file) else { continue }
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let dataURL = "data:\(mime);base64,\(data.base64EncodedString())"
            result = (result as NSString).replacingCharacters(in: match.range, with: dataURL)
        }
        return result
    }
}
