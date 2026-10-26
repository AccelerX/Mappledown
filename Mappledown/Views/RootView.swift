import SwiftUI
import UniformTypeIdentifiers

enum ImportTarget: Equatable {
    case file, folder
}

@MainActor
struct RootView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: AppSettings
    @State private var selection: SidebarItem? = .recents
    @State private var showSettings = false
    @State private var importTarget: ImportTarget?
    /// Remembered separately: the picker clears `importTarget` before its result arrives.
    @State private var pickingFolder = false
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        // The open document replaces the library instead of being presented over it.
        // Presenting it as a cover failed when it was opened from a folder list or
        // right after the Files picker closed.
        ZStack {
            if let doc = library.current {
                DocumentView(document: doc, initialMode: library.currentMode)
                    .id(doc.id)
                    .transition(.opacity)
            } else {
                library_
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: library.current?.id)
        .fullScreenCover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .alert("Mappledown", isPresented: alertBinding) {
            Button("OK", role: .cancel) { library.alert = nil }
        } message: {
            Text(library.alert ?? "")
        }
        .onChange(of: importTarget) { target in
            if let target { pickingFolder = (target == .folder) }
        }
    }

    private var library_: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(selection: $selection, showSettings: $showSettings, importTarget: $importTarget)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .fileImporter(isPresented: importBinding,
                      allowedContentTypes: (importTarget ?? (pickingFolder ? .folder : .file)) == .folder ? [.folder] : [.markdownText, .plainText, .text],
                      allowsMultipleSelection: false) { result in
            let folder = pickingFolder
            importTarget = nil
            guard case .success(let urls) = result, let url = urls.first else { return }
            if folder {
                library.addFolder(url)
                if let folder = library.folders.last { selection = .folder(folder.id) }
            } else {
                library.open(url, defaultMode: settings.defaultMode)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .recents {
        case .recents:
            NavigationStack { RecentsView(pinnedOnly: false, importTarget: $importTarget) }
        case .pinned:
            NavigationStack { RecentsView(pinnedOnly: true, importTarget: $importTarget) }
        case .trash:
            NavigationStack { TrashView() }
        case .onMyIPad:
            FolderBrowser(root: library.documentsURL, title: "On My iPad", isICloud: false)
                .id("on-my-ipad")
        case .folder(let id):
            if let folder = library.folders.first(where: { $0.id == id }), let url = library.resolveFolder(folder) {
                FolderBrowser(root: url, title: folder.name, isICloud: folder.isICloud)
                    .id(id)
            } else {
                ContentUnavailable(title: "Folder not available",
                                   message: "Mappledown lost access to this folder. Remove it and add it again.",
                                   systemImage: "folder.badge.questionmark")
            }
        }
    }

    private var importBinding: Binding<Bool> {
        Binding(get: { importTarget != nil }, set: { if !$0 { importTarget = nil } })
    }

    private var alertBinding: Binding<Bool> {
        Binding(get: { library.alert != nil }, set: { if !$0 { library.alert = nil } })
    }
}

/// A simple empty-state view (ContentUnavailableView needs iOS 17).
@MainActor
struct ContentUnavailable: View {
    var title: String
    var message: String
    var systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.semibold))
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
