import SwiftUI

/// Recents (or Pinned) as a grid of cards, like the mockup.
@MainActor
struct RecentsView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: AppSettings
    var pinnedOnly: Bool
    @Binding var importTarget: ImportTarget?
    @State private var query = ""

    private var items: [RecentItem] {
        let base = pinnedOnly ? library.recents.filter(\.pinned) : library.recents
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.title.localizedCaseInsensitiveContains(q) }
    }

    private let columns = [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 22)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    Text(pinnedOnly ? "Pinned" : "Recents")
                        .font(.largeTitle.weight(.bold))
                    Spacer()
                    Text(pinnedOnly ? countLabel : "Sorted by date opened")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if items.isEmpty {
                    ContentUnavailable(
                        title: pinnedOnly ? "No pinned files" : "No recent files",
                        message: pinnedOnly
                            ? "To pin a file, touch and hold it in Recents or a folder, then choose Pin. Unpinning never deletes anything."
                            : "Open a Markdown file from Files, or create a new one. It will show up here.",
                        systemImage: pinnedOnly ? "pin" : "clock")
                    .frame(minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                        ForEach(items) { item in
                            RecentCard(item: item)
                        }
                    }
                }

                if !pinnedOnly && settings.showFilesTip {
                    FilesTip { settings.showFilesTip = false }
                        .padding(.top, 12)
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 18)
        }
        .searchable(text: $query, placement: .toolbar, prompt: pinnedOnly ? "Search pinned" : "Search")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !pinnedOnly {
                    Button {
                        if let url = library.newFile(in: library.documentsURL) {
                            library.open(url, mode: .edit, defaultMode: settings.defaultMode)
                        }
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                }
                Button {
                    importTarget = .file
                } label: {
                    Label("Open from Files…", systemImage: "folder")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private var countLabel: String {
        items.count == 1 ? "1 file" : "\(items.count) files"
    }
}

@MainActor
struct RecentCard: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: AppSettings
    var item: RecentItem

    var body: some View {
        Button {
            library.open(item, defaultMode: settings.defaultMode)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.title)
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                    ForEach(Array(item.snippet.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .topLeading)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(uiColor: .separator), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if item.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .padding(10)
                    }
                }
                .shadow(color: .black.opacity(0.06), radius: 5, y: 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(item.location) · \(Self.dateLabel(item.lastOpened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                library.open(item, defaultMode: settings.defaultMode)
            } label: { Label("Open", systemImage: "doc.text") }
            Button {
                library.togglePin(item)
            } label: {
                Label(item.pinned ? "Unpin" : "Pin", systemImage: item.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                library.removeFromRecents(item)
            } label: { Label("Remove from Recents", systemImage: "xmark") }
        }
    }

    static func dateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "Today, " + date.formatted(date: .omitted, time: .shortened)
        }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

@MainActor
struct FilesTip: View {
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up")
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Open straight from Files").font(.subheadline.weight(.semibold))
                Text("In the Files app, touch and hold any .md file, tap Share, then Mappledown. Edits save back to the same file.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Got it", action: dismiss)
                .font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
