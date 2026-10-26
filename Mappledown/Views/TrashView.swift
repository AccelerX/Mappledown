import SwiftUI

/// Recently Deleted: files deleted in Mappledown stay here for 30 days.
@MainActor
struct TrashView: View {
    @EnvironmentObject var library: Library
    @State private var pendingForever: TrashItem?
    @State private var confirmEmpty = false

    var body: some View {
        List {
            Section {
                if library.trash.isEmpty {
                    ContentUnavailable(title: "Nothing in Recently Deleted",
                                       message: "Files you delete in Mappledown stay here for \(TrashItem.keepDays) days, then they're removed for good.",
                                       systemImage: "trash")
                        .frame(minHeight: 300)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(library.trash) { item in
                        row(item)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    withAnimation { library.restore(item) }
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.accentColor)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    pendingForever = item
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                .tint(.red)
                            }
                            .contextMenu {
                                Button {
                                    withAnimation { library.restore(item) }
                                } label: {
                                    Label("Restore", systemImage: "arrow.uturn.backward")
                                }
                                Button(role: .destructive) {
                                    pendingForever = item
                                } label: {
                                    Label("Delete Permanently…", systemImage: "trash")
                                }
                            }
                    }
                }
            } header: {
                Text("Recently Deleted")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                    .textCase(nil)
                    .padding(.bottom, 6)
            } footer: {
                Text("Swipe right on a file to restore it to where it was, or left to delete it permanently.")
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
        }
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmEmpty = true
                } label: {
                    Label("Empty", systemImage: "trash.slash").labelStyle(.titleAndIcon)
                }
                .disabled(library.trash.isEmpty)
            }
        }
        .alert("Delete \u{201C}\(pendingForever?.name ?? "")\u{201D} permanently?", isPresented: foreverBinding) {
            Button("Delete Permanently", role: .destructive) {
                if let item = pendingForever { withAnimation { library.deleteForever(item) } }
                pendingForever = nil
            }
            Button("Cancel", role: .cancel) { pendingForever = nil }
        } message: {
            Text("This can't be undone.")
        }
        .alert("Empty Recently Deleted?", isPresented: $confirmEmpty) {
            Button("Delete All", role: .destructive) { withAnimation { library.emptyTrash() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(library.trash.count == 1 ? "1 file will be deleted permanently. This can't be undone."
                 : "\(library.trash.count) files will be deleted permanently. This can't be undone.")
        }
    }

    private var foreverBinding: Binding<Bool> {
        Binding(get: { pendingForever != nil }, set: { if !$0 { pendingForever = nil } })
    }

    private func row(_ item: TrashItem) -> some View {
        HStack(spacing: 14) {
            MDIcon(dashed: false).opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body.weight(.medium))
                Text("From \(item.fromLabel) · \(item.daysLeft == 1 ? "1 day" : "\(item.daysLeft) days") left")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .frame(minHeight: 54)
    }
}
