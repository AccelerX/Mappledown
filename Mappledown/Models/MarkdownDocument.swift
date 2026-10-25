import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist (UTImportedTypeDeclarations) so Files offers Mappledown for .md files.
    static let markdownText = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

enum MarkdownFiles {
    static let extensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    static func isMarkdown(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}

/// One open Markdown file. Reads and writes in place, through file coordination,
/// so files in iCloud Drive or other apps' folders stay in sync.
@MainActor
final class MarkdownDocument: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let location: String
    @Published var text: String
    @Published private(set) var savedText: String
    @Published private(set) var lastSaved: Date?
    @Published var saveError: String?

    private let accessing: Bool

    var name: String { url.lastPathComponent }
    var baseName: String { url.deletingPathExtension().lastPathComponent }
    var isDirty: Bool { text != savedText }

    init(url: URL, location: String) throws {
        self.url = url
        self.location = location
        accessing = url.startAccessingSecurityScopedResource()
        do {
            let content = try MarkdownDocument.read(url)
            text = content
            savedText = content
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    deinit {
        if accessing { url.stopAccessingSecurityScopedResource() }
    }

    static func read(_ url: URL) throws -> String {
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                let data = try Data(contentsOf: readURL)
                if let s = String(data: data, encoding: .utf8) {
                    result = .success(s)
                } else if let s = String(data: data, encoding: .utf16) {
                    result = .success(s)
                } else {
                    result = .success(String(decoding: data, as: UTF8.self))
                }
            } catch {
                result = .failure(error)
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Writes the current text back to the original file. Returns true on success.
    @discardableResult
    func save() -> Bool {
        guard isDirty else { return true }
        let content = text
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: [.forReplacing], error: &coordinationError) { writeURL in
            do {
                try Data(content.utf8).write(to: writeURL, options: [])
            } catch {
                writeError = error
            }
        }
        if let err = coordinationError ?? writeError {
            saveError = err.localizedDescription
            return false
        }
        savedText = content
        lastSaved = Date()
        saveError = nil
        return true
    }
}
