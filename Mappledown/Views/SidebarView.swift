import SwiftUI

@MainActor
struct SidebarView: View {
    @EnvironmentObject var library: Library
    @Binding var selection: SidebarItem?
    @Binding var showSettings: Bool
    @Binding var importTarget: ImportTarget?

    var body: some View {
        List(selection: $selection) {
            Section("Library") {
                Label("Recents", systemImage: "clock").tag(SidebarItem.recents)
                Label("Pinned", systemImage: "pin").tag(SidebarItem.pinned)
            }
            Section("Open from") {
                Label("On My iPad", systemImage: "ipad").tag(SidebarItem.onMyIPad)
                ForEach(library.folders) { folder in
                    Label(folder.name, systemImage: folder.isICloud ? "icloud" : "folder")
                        .tag(SidebarItem.folder(folder.id))
                        .contextMenu {
                            Button(role: .destructive) {
                                if selection == .folder(folder.id) { selection = .onMyIPad }
                                library.removeFolder(folder)
                            } label: {
                                Label("Remove from Sidebar", systemImage: "minus.circle")
                            }
                        }
                }
                Button {
                    importTarget = .folder
                } label: {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
                Button {
                    importTarget = .file
                } label: {
                    Label("Browse All Locations…", systemImage: "folder")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Mappledown")
        .safeAreaInset(edge: .bottom) {
            Button {
                showSettings = true
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(.bar)
        }
    }
}
