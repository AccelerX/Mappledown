import Foundation
import SwiftUI

struct RecentItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    var bookmark: Data?
    var location: String
    var lastOpened: Date
    var pinned: Bool = false
    var title: String
    var snippet: [String]
}

struct LinkedFolder: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var bookmark: Data
    var isICloud: Bool
}

enum SidebarItem: Hashable {
    case recents
    case pinned
    case onMyIPad
    case folder(UUID)
}

/// Recents, pins, linked folders and the currently open document.
@MainActor
final class Library: ObservableObject {
    @Published private(set) var recents: [RecentItem] = []
    @Published private(set) var folders: [LinkedFolder] = []
    @Published var current: MarkdownDocument?
    @Published var currentMode: ViewMode = .split
    @Published var alert: String?

    private var folderURLs: [UUID: URL] = [:]
    private let store = UserDefaults.standard

    let documentsURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    init() {
        if let data = store.data(forKey: "recents"), let r = try? JSONDecoder().decode([RecentItem].self, from: data) {
            recents = r
        }
        if let data = store.data(forKey: "folders"), let f = try? JSONDecoder().decode([LinkedFolder].self, from: data) {
            folders = f
        }
        for folder in folders { _ = resolveFolder(folder) }
        installSampleIfNeeded()
    }

    // MARK: Persistence

    private func saveRecents() {
        if let data = try? JSONEncoder().encode(recents) { store.set(data, forKey: "recents") }
    }

    private func saveFolders() {
        if let data = try? JSONEncoder().encode(folders) { store.set(data, forKey: "folders") }
    }

    private func installSampleIfNeeded() {
        guard !store.bool(forKey: "sampleInstalled") else { return }
        store.set(true, forKey: "sampleInstalled")
        guard let sample = Bundle.main.url(forResource: "Math stress test", withExtension: "md", subdirectory: "Samples") else { return }
        let target = documentsURL.appendingPathComponent("Math stress test.md")
        if !FileManager.default.fileExists(atPath: target.path) {
            try? FileManager.default.copyItem(at: sample, to: target)
        }
    }

    // MARK: Folders

    /// Resolves a linked folder's bookmark and keeps access to it open while the app runs.
    func resolveFolder(_ folder: LinkedFolder) -> URL? {
        if let url = folderURLs[folder.id] { return url }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return nil
        }
        _ = url.startAccessingSecurityScopedResource()
        folderURLs[folder.id] = url
        if stale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil),
           let i = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[i].bookmark = fresh
            saveFolders()
        }
        return url
    }

    func addFolder(_ url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        guard let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else {
            alert = "Mappledown couldn't keep access to that folder."
            return
        }
        if let existing = folders.first(where: { folderURLs[$0.id]?.standardizedFileURL == url.standardizedFileURL }) {
            _ = existing
            return
        }
        let isICloud = url.path.contains("/Mobile Documents/")
        let folder = LinkedFolder(name: url.lastPathComponent, bookmark: bookmark, isICloud: isICloud)
        folders.append(folder)
        folderURLs[folder.id] = url
        saveFolders()
    }

    func removeFolder(_ folder: LinkedFolder) {
        folderURLs[folder.id]?.stopAccessingSecurityScopedResource()
        folderURLs[folder.id] = nil
        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }

    /// A readable place name such as "On My iPad › Notes" or "iCloud Drive › Courses".
    func locationLabel(for url: URL) -> String {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        let docs = documentsURL.standardizedFileURL.path
        if parent.hasPrefix(docs) {
            let rest = parent.dropFirst(docs.count).split(separator: "/").map(String.init)
            return (["On My iPad"] + rest).joined(separator: " › ")
        }
        for folder in folders {
            guard let root = folderURLs[folder.id]?.standardizedFileURL.path, parent.hasPrefix(root) else { continue }
            let rest = parent.dropFirst(root.count).split(separator: "/").map(String.init)
            let head = folder.isICloud ? "iCloud Drive › \(folder.name)" : folder.name
            return ([head] + rest).joined(separator: " › ")
        }
        if url.path.contains("/Mobile Documents/") {
            return "iCloud Drive › \(url.deletingLastPathComponent().lastPathComponent)"
        }
        return url.deletingLastPathComponent().lastPathComponent
    }

    // MARK: Opening

    func open(_ url: URL, mode: ViewMode? = nil, defaultMode: ViewMode) {
        do {
            let doc = try MarkdownDocument(url: url, location: locationLabel(for: url))
            record(doc)
            currentMode = mode ?? defaultMode
            current = doc
        } catch {
            alert = "Couldn't open \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func open(_ item: RecentItem, defaultMode: ViewMode) {
        guard let url = resolve(item) else {
            alert = "\(item.name) has moved or been deleted. Open it again from Files."
            return
        }
        open(url, defaultMode: defaultMode)
    }

    func resolve(_ item: RecentItem) -> URL? {
        if let data = item.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url
            }
        }
        let url = URL(fileURLWithPath: item.path)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Adds or refreshes the file at the top of Recents.
    func record(_ doc: MarkdownDocument) {
        let path = doc.url.standardizedFileURL.path
        let bookmark = try? doc.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let (title, snippet) = Library.summary(of: doc.text, fallback: doc.baseName)
        var item = recents.first(where: { $0.path == path })
            ?? RecentItem(name: doc.name, path: path, location: doc.location, lastOpened: Date(), title: title, snippet: snippet)
        item.name = doc.name
        item.bookmark = bookmark ?? item.bookmark
        item.location = doc.location
        item.lastOpened = Date()
        item.title = title
        item.snippet = snippet
        recents.removeAll { $0.path == path }
        recents.insert(item, at: 0)
        if recents.count > 60 {
            recents = Array(recents.prefix(60))
        }
        saveRecents()
    }

    func togglePin(_ item: RecentItem) {
        guard let i = recents.firstIndex(where: { $0.id == item.id }) else { return }
        recents[i].pinned.toggle()
        saveRecents()
    }

    func removeFromRecents(_ item: RecentItem) {
        recents.removeAll { $0.id == item.id }
        saveRecents()
    }

    func isPinned(_ url: URL) -> Bool {
        recents.first(where: { $0.path == url.standardizedFileURL.path })?.pinned ?? false
    }

    func pin(url: URL) {
        let path = url.standardizedFileURL.path
        if let i = recents.firstIndex(where: { $0.path == path }) {
            recents[i].pinned.toggle()
            saveRecents()
            return
        }
        guard let text = try? MarkdownDocument.read(url) else { return }
        let (title, snippet) = Library.summary(of: text, fallback: url.deletingPathExtension().lastPathComponent)
        let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        recents.append(RecentItem(name: url.lastPathComponent, path: path, bookmark: bookmark, location: locationLabel(for: url),
                                  lastOpened: Date(), pinned: true, title: title, snippet: snippet))
        saveRecents()
    }

    func close() {
        if let doc = current {
            if doc.isDirty { doc.save() }
            record(doc)
        }
        current = nil
    }

    // MARK: New files

    /// Creates "Untitled.md" (or "Untitled 2.md", ...) in the folder and returns it.
    func newFile(in folder: URL) -> URL? {
        let fm = FileManager.default
        var n = 1
        var url: URL
        repeat {
            url = folder.appendingPathComponent(n == 1 ? "Untitled.md" : "Untitled \(n).md")
            n += 1
        } while fm.fileExists(atPath: url.path)
        do {
            try Data("# Untitled\n\n".utf8).write(to: url)
            return url
        } catch {
            alert = "Couldn't create a file here: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Card text

    /// The first heading (or file name) and a few lines of plain text for a Recents card.
    static func summary(of text: String, fallback: String) -> (String, [String]) {
        var title: String?
        var lines: [String] = []
        var inMath = false
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true).prefix(60) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line == "$$" || line == "\\[" || line == "\\]" { inMath.toggle(); continue }
            if line.hasPrefix("\\begin{") { inMath = true; continue }
            if line.hasPrefix("\\end{") { inMath = false; continue }
            if line.hasPrefix("$$") && line.hasSuffix("$$") && line.count > 4 { continue }
            if inMath { continue }
            if line.hasPrefix("#") {
                let h = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                if title == nil { title = h } else if lines.count < 3 { lines.append(h) }
                continue
            }
            if lines.count < 3 && !line.hasPrefix("```") && !line.hasPrefix("|") {
                lines.append(String(line.prefix(90)))
            }
            if title != nil && lines.count >= 3 { break }
        }
        return (title ?? fallback, lines)
    }
}
