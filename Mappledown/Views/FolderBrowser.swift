import SwiftUI

struct FolderEntry: Identifiable, Hashable {
    enum Kind { case folder, file, cloudOnly }
    var id: URL { url }
    var url: URL
    var name: String
    var kind: Kind
    var modified: Date?
    var size: Int?
    var itemCount: Int?
}

enum FolderSort: String, CaseIterable {
    case name, date
    var label: String { self == .name ? "Name" : "Date" }
}

/// Browses a folder (On My iPad, or a folder the user linked) and its subfolders.
@MainActor
struct FolderBrowser: View {
    var root: URL
    var title: String
    var isICloud: Bool

    var body: some View {
        NavigationStack {
            FolderListView(url: root, title: title, isRoot: true)
                .navigationDestination(for: URL.self) { url in
                    FolderListView(url: url, title: url.lastPathComponent, isRoot: false)
                }
        }
    }
}

@MainActor
struct FolderListView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: AppSettings
    var url: URL
    var title: String
    var isRoot: Bool

    @State private var entries: [FolderEntry] = []
    @State private var query = ""
    @AppStorage("folderSort") private var sort: FolderSort = .name
    @State private var downloading: Set<URL> = []

    private var shown: [FolderEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(q) }
        return filtered.sorted { a, b in
            if (a.kind == .folder) != (b.kind == .folder) { return a.kind == .folder }
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .date: return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.largeTitle.weight(.bold)).lineLimit(1)
                    Spacer()
                    Text(shown.count == 1 ? "1 item" : "\(shown.count) items")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if shown.isEmpty {
                    ContentUnavailable(title: "No Markdown files here",
                                       message: "Only .md and .markdown files and folders are shown.",
                                       systemImage: "doc.text")
                    .frame(minHeight: 300)
                } else {
                    VStack(spacing: 0) {
                        ForEach(shown) { entry in
                            row(entry)
                            if entry.id != shown.last?.id {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .background(Color(uiColor: .secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                }

                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
        .refreshable { reload() }
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(FolderSort.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                } label: {
                    Label("Sort by \(sort.label)", systemImage: "arrow.up.arrow.down")
                        .labelStyle(.titleAndIcon)
                }
                Button {
                    if let file = library.newFile(in: url) {
                        reload()
                        library.open(file, mode: .edit, defaultMode: settings.defaultMode)
                    }
                } label: {
                    Label("New file here", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onChange(of: library.current == nil) { closed in
            if closed { reload() }
        }
    }

    private var footer: String {
        isRoot && url == library.documentsURL
            ? "This is the Mappledown folder in Files › On My iPad. Files you put there show up here."
            : "Files stored only in iCloud download the first time you open them. Saving uploads the change."
    }

    @ViewBuilder
    private func row(_ entry: FolderEntry) -> some View {
        switch entry.kind {
        case .folder:
            NavigationLink(value: entry.url) {
                rowContent(entry, icon: AnyView(
                    Image(systemName: "folder.fill").font(.system(size: 28)).foregroundStyle(Color(red: 0.35, green: 0.66, blue: 0.9))
                ), detail: entry.itemCount.map { $0 == 1 ? "1 item" : "\($0) items" } ?? "", chevron: true)
            }
            .buttonStyle(.plain)
        case .file:
            Button {
                library.open(entry.url, defaultMode: settings.defaultMode)
            } label: {
                rowContent(entry, icon: AnyView(MDIcon(dashed: false)), detail: fileDetail(entry), chevron: false)
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    library.pin(url: entry.url)
                } label: {
                    Label(library.isPinned(entry.url) ? "Unpin" : "Pin", systemImage: "pin")
                }
            }
        case .cloudOnly:
            HStack(spacing: 14) {
                MDIcon(dashed: true).opacity(0.6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).font(.body.weight(.medium)).foregroundStyle(.secondary)
                    Text(downloading.contains(entry.url) ? "Downloading…" : "\(fileDetail(entry)) · In iCloud only")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                if downloading.contains(entry.url) {
                    ProgressView()
                } else {
                    Button {
                        download(entry)
                    } label: {
                        Label("Download", systemImage: "icloud.and.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 62)
        }
    }

    private func rowContent(_ entry: FolderEntry, icon: AnyView, detail: String, chevron: Bool) -> some View {
        HStack(spacing: 14) {
            icon.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                if !detail.isEmpty {
                    Text(detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if chevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 62)
        .contentShape(Rectangle())
    }

    private func fileDetail(_ entry: FolderEntry) -> String {
        var parts: [String] = []
        if let d = entry.modified { parts.append(RecentCard.dateLabel(d)) }
        if let s = entry.size { parts.append(ByteCountFormatter.string(fromByteCount: Int64(s), countStyle: .file)) }
        return parts.joined(separator: " · ")
    }

    private func download(_ entry: FolderEntry) {
        downloading.insert(entry.url)
        try? FileManager.default.startDownloadingUbiquitousItem(at: entry.url)
        // Check back until the file has arrived.
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if FileManager.default.fileExists(atPath: entry.url.path) {
                    break
                }
            }
            downloading.remove(entry.url)
            reload()
        }
    }

    private func reload() {
        entries = FolderListView.list(url)
    }

    static func list(_ folder: URL) -> [FolderEntry] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: []) else {
            return []
        }
        var result: [FolderEntry] = []
        for u in urls {
            let name = u.lastPathComponent
            // iCloud files that aren't downloaded show up as ".Name.md.icloud".
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                let real = String(name.dropFirst().dropLast(".icloud".count))
                let realURL = folder.appendingPathComponent(real)
                guard MarkdownFiles.isMarkdown(realURL) else { continue }
                result.append(FolderEntry(url: realURL, name: real, kind: .cloudOnly, modified: nil, size: nil))
                continue
            }
            if name.hasPrefix(".") { continue }
            let values = try? u.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                let count = (try? fm.contentsOfDirectory(atPath: u.path))?.filter { !$0.hasPrefix(".") || $0.hasSuffix(".icloud") }.count
                result.append(FolderEntry(url: u, name: name, kind: .folder, modified: values?.contentModificationDate, itemCount: count))
            } else if MarkdownFiles.isMarkdown(u) {
                result.append(FolderEntry(url: u, name: name, kind: .file, modified: values?.contentModificationDate, size: values?.fileSize))
            }
        }
        return result
    }
}

/// The little "MD" document icon from the mockup.
@MainActor
struct MDIcon: View {
    var dashed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: dashed ? [3, 2] : []))
            .frame(width: 26, height: 32)
            .overlay(alignment: .bottom) {
                Text("MD")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(dashed ? Color.secondary : Color.accentColor)
                    .padding(.bottom, 3)
            }
            .frame(width: 34, height: 34)
    }
}
