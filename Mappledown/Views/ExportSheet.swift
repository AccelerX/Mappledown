import SwiftUI

/// The Export sheet: a live page preview on the left, options on the right.
@MainActor
struct ExportSheet: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var document: MarkdownDocument

    @StateObject private var preview = PreviewController()
    @State private var format: ExportFormat = .pdf
    @State private var paper: Paper = .a4
    @State private var margins: Margins = .normal
    @State private var pageNumbers = true
    @State private var headingBreak = false
    @State private var toc = false
    @State private var fileNameAsTitle = true
    @State private var followDark = true
    @State private var loaded = false
    @State private var working = false
    @State private var errorText: String?

    private var config: RenderConfig {
        settings.renderConfig(dark: false)
    }

    private var fileName: String {
        var base = document.baseName
        if settings.dateInFileName {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            base += " " + f.string(from: Date())
        }
        return base + "." + format.fileExtension
    }

    private var title: String {
        fileNameAsTitle ? document.baseName : Library.summary(of: document.text, fallback: document.baseName).0
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 0) {
                pagePreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
                Divider()
                options
                    .frame(width: 330)
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button {
                            Task { await share() }
                        } label: {
                            Label("Share…", systemImage: "square.and.arrow.up")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            format = settings.exportFormat
            paper = settings.paper
            margins = settings.margins
            pageNumbers = settings.pageNumbers
            headingBreak = settings.headingPageBreak
            toc = settings.tableOfContents
            fileNameAsTitle = settings.fileNameAsTitle
            followDark = settings.htmlFollowsDarkMode
            preview.printMode = true
            preview.headingPageBreak = headingBreak
            preview.tableOfContents = toc && format == .pdf
            preview.baseFolder = document.url.deletingLastPathComponent()
        }
        .onChange(of: headingBreak) { _ in updatePrintMode() }
        .onChange(of: toc) { _ in updatePrintMode() }
        .onChange(of: format) { _ in updatePrintMode() }
        .alert("Export failed", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Preview

    private var pagePreview: some View {
        GeometryReader { geo in
            let paperSize = paper.size
            let scale = min((geo.size.width - 48) / paperSize.width, (geo.size.height - 70) / paperSize.height)
            let pageW = paperSize.width * scale
            let pageH = paperSize.height * scale
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                ZStack {
                    Color.white
                    PreviewWebView(controller: preview, text: document.text, config: config)
                        // Show the page at print scale: lay out at paper width, then shrink.
                        .frame(width: paperSize.width - margins.points * 2,
                               height: paperSize.height - margins.points * 2)
                        .scaleEffect(scale, anchor: .center)
                        .frame(width: pageW - margins.points * 2 * scale, height: pageH - margins.points * 2 * scale)
                        .clipped()
                        .allowsHitTesting(format == .html)
                    if pageNumbers && format == .pdf {
                        VStack {
                            Spacer()
                            Text("1").font(.system(size: max(7, 9 * scale))).foregroundStyle(.gray)
                                .padding(.bottom, margins.points * scale / 2 - 6)
                        }
                    }
                }
                .frame(width: pageW, height: pageH)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                Text(format == .pdf ? "\(paper.label) · \(margins.label) margins" : "HTML · one scrolling page\(followDark ? ", light or dark" : "")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    // MARK: Options

    private var options: some View {
        Form {
            Section("Format") {
                Picker("Format", selection: $format) {
                    ForEach(ExportFormat.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if format == .pdf {
                Section("Paper size") {
                    Picker("Paper size", selection: $paper) {
                        ForEach(Paper.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section("Margins") {
                    Picker("Margins", selection: $margins) {
                        ForEach(Margins.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                Section {
                    Toggle("Page numbers", isOn: $pageNumbers)
                    Toggle("Start each # heading on a new page", isOn: $headingBreak)
                    Toggle("Table of contents from headings", isOn: $toc)
                    Toggle("Use file name as document title", isOn: $fileNameAsTitle)
                }
            } else {
                Section {
                    Toggle("Follow the reader's Dark Mode", isOn: $followDark)
                    Toggle("Use file name as document title", isOn: $fileNameAsTitle)
                } footer: {
                    Text("Math is saved as pictures inside the file, so it shows correctly offline and in any browser.")
                }
            }
            Section {
                Text("Saves as **\(fileName)**. Share opens the iPad share sheet: Save to Files, AirDrop, Mail or Print.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func updatePrintMode() {
        preview.setPrintMode(true, headingBreak: headingBreak, toc: toc && format == .pdf)
    }

    // MARK: Share

    private func share() async {
        working = true
        defer { working = false }
        await preview.renderAndWait(text: document.text, config: config)
        updatePrintMode()
        try? await Task.sleep(nanoseconds: 150_000_000)
        let options = ExportOptions(format: format, paper: paper, margins: margins, pageNumbers: pageNumbers,
                                    headingPageBreak: headingBreak, tableOfContents: toc && format == .pdf, title: title, fileName: fileName,
                                    htmlFollowsDarkMode: followDark)
        do {
            let url = try await Exporter.export(from: preview, options: options)
            ShareSheet.present([url])
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// Presents the system share sheet from whatever is on screen.
@MainActor
enum ShareSheet {
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        var top = root
        while let next = top.presentedViewController { top = next }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.maxX - 80, y: 60, width: 1, height: 1)
            pop.permittedArrowDirections = [.up]
        }
        top.present(vc, animated: true)
    }
}
