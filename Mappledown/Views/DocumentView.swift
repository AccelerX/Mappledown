import SwiftUI

/// The document screen from the mockup: header, editor and/or preview, status bar.
@MainActor
struct DocumentView: View {
    @EnvironmentObject var library: Library
    @EnvironmentObject var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var document: MarkdownDocument

    @State private var mode: ViewMode
    @StateObject private var preview = PreviewController()
    @StateObject private var editor = EditorController()
    @State private var showExport = false
    @State private var confirmClose = false
    @State private var justSaved = false
    @State private var autosaveTask: Task<Void, Never>?

    init(document: MarkdownDocument, initialMode: ViewMode) {
        self.document = document
        _mode = State(initialValue: initialMode)
    }

    private var renderConfig: RenderConfig {
        settings.renderConfig(dark: settings.previewIsDark(system: colorScheme))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            statusBar
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showExport) {
            ExportSheet(document: document)
                .environmentObject(settings)
        }
        .confirmationDialog("Save changes to \(document.name)?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save") { if document.save() { library.close() } }
            Button("Don't Save", role: .destructive) {
                document.text = document.savedText
                library.close()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: document.text) { _ in
            justSaved = false
            scheduleAutosave()
        }
        .onAppear {
            preview.baseFolder = document.url.deletingLastPathComponent()
            connectScrolling()
        }
        .onChange(of: mode) { _ in connectScrolling() }
        .onChange(of: settings.syncScroll) { _ in connectScrolling() }
    }

    /// In Split view, scrolling one side scrolls the other to the same source line.
    private func connectScrolling() {
        guard settings.syncScroll && mode == .split else {
            editor.onUserScroll = nil
            preview.onUserScroll = nil
            return
        }
        let preview = self.preview
        let editor = self.editor
        editor.onUserScroll = { [weak preview] line in preview?.scrollToLine(line) }
        preview.onUserScroll = { [weak editor] line in editor?.scroll(toLine: line) }
    }

    // MARK: Header

    private var header: some View {
        GeometryReader { geo in
            // Narrow windows (portrait, Split View) get icon-only buttons so nothing wraps.
            let compact = geo.size.width < 1000
            HStack(spacing: compact ? 8 : 12) {
                Button {
                    close()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold))
                        Text("Library").font(.system(size: 17, weight: .medium))
                    }
                    .frame(height: 44)
                }
                .fixedSize()

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name).font(.headline).lineLimit(1).truncationMode(.middle)
                    Text(document.location).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }

                Spacer(minLength: 8)

                Picker("View mode", selection: $mode) {
                    ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: compact ? 210 : 270)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                if mode != .preview {
                    Button { editor.undo() } label: {
                        Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Undo")
                    Button { editor.redo() } label: {
                        Image(systemName: "arrow.uturn.forward").frame(width: 40, height: 44)
                    }
                    .accessibilityLabel("Redo")
                }

                Button {
                    save()
                } label: {
                    if compact {
                        Image(systemName: "square.and.arrow.down")
                    } else {
                        Text("Save")
                    }
                }
                .accessibilityLabel("Save")
                .buttonStyle(.bordered)
                .keyboardShortcut("s", modifiers: .command)
                .fixedSize()

                Button {
                    if document.isDirty && settings.autosave { document.save() }
                    showExport = true
                } label: {
                    if compact {
                        Image(systemName: "square.and.arrow.up")
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .accessibilityLabel("Export")
                .buttonStyle(.borderedProminent)
                .fixedSize()
            }
            .font(.body)
            .padding(.horizontal, 16)
            .frame(width: geo.size.width, height: 64)
        }
        .frame(height: 64)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 0) {
            if mode != .preview {
                VStack(spacing: 0) {
                    EditorView(text: $document.text, settings: settings, controller: editor)
                        .background(Color(uiColor: .systemBackground))
                    if settings.mathKeys {
                        Divider()
                        MathKeyBar(editor: editor)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            if mode == .split {
                Divider()
            }
            if mode != .edit {
                PreviewWebView(controller: preview, text: document.text, config: renderConfig,
                               delay: settings.liveUpdate ? 0.3 : 3600)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: renderConfig.dark ? .black : .white))
                    .onChange(of: mode) { newMode in
                        // Without live update, refresh the preview when switching to it.
                        if newMode == .preview {
                            preview.update(text: document.text, config: renderConfig, delay: 0)
                        }
                    }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 20) {
            if mode != .preview {
                // One tap shows or hides the math keys row (same switch as in Settings › Editor).
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { settings.mathKeys.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "function")
                        Text("Math keys")
                        Image(systemName: settings.mathKeys ? "chevron.down" : "chevron.up")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .foregroundStyle(settings.mathKeys ? Color.white : Color.accentColor)
                    .background(Capsule().fill(settings.mathKeys ? Color.accentColor : Color.accentColor.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(settings.mathKeys ? "Hide math keys" : "Show math keys")
                Text("Ln \(editor.line), Col \(editor.column)")
            }
            Text("Markdown · UTF-8")
            Spacer()
            HStack(spacing: 6) {
                Circle()
                    .fill(preview.mathErrors > 0 ? Color.orange : Color.green)
                    .frame(width: 8, height: 8)
                Text(preview.mathErrors > 0
                     ? "MathJax 3 · \(preview.mathErrors) math error\(preview.mathErrors == 1 ? "" : "s")"
                     : "MathJax 3 · offline")
            }
            HStack(spacing: 4) {
                Image(systemName: document.isDirty ? "pencil" : "checkmark")
                    .font(.footnote.weight(.bold))
                Text(saveLabel)
            }
            .foregroundStyle(document.saveError == nil ? Color.primary : Color.red)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(Color(uiColor: .secondarySystemBackground).opacity(0.6))
    }

    private var saveLabel: String {
        if let err = document.saveError { return "Not saved: \(err)" }
        if document.isDirty { return settings.autosave ? "Edited" : "Unsaved changes" }
        return justSaved ? "Saved just now" : "Saved"
    }

    // MARK: Actions

    private func save() {
        if document.save() { justSaved = true }
    }

    private func close() {
        autosaveTask?.cancel()
        if document.isDirty && !settings.autosave {
            confirmClose = true
        } else {
            library.close()
        }
    }

    private func scheduleAutosave() {
        guard settings.autosave else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, document.isDirty else { return }
            if document.save() { justSaved = true }
        }
    }
}

/// The math keys row under the editor.
@MainActor
struct MathKeyBar: View {
    @ObservedObject var editor: EditorController

    private struct Key: Identifiable {
        let label: String
        let text: String
        let back: Int
        var id: String { label }
    }

    private let keys: [Key] = [
        Key(label: "$ $", text: "$$", back: 1),
        Key(label: "$$", text: "$$\n\n$$", back: 3),
        Key(label: "\\frac", text: "\\frac{}{}", back: 3),
        Key(label: "^{ }", text: "^{}", back: 1),
        Key(label: "_{ }", text: "_{}", back: 1),
        Key(label: "\\sqrt", text: "\\sqrt{}", back: 1),
        Key(label: "align", text: "\\begin{align}\n\n\\end{align}", back: 12),
        Key(label: "cases", text: "\\begin{cases}\n  & \\\\\n  & \n\\end{cases}", back: 21),
        Key(label: "matrix", text: "\\begin{pmatrix}\n  &  \\\\\n  &  \n\\end{pmatrix}", back: 25)
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(keys) { key in
                    Button {
                        editor.insert(key.text, cursorBack: key.back)
                    } label: {
                        Text(key.label)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 44)
                            .background(Color(uiColor: .systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(uiColor: .separator), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
}
