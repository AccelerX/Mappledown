import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case editor, preview, math, export, about
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .editor: return "pencil"
        case .preview: return "eye"
        case .math: return "function"
        case .export: return "square.and.arrow.up"
        case .about: return "info.circle"
        }
    }
}

@MainActor
struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var section: SettingsSection? = .editor

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(SettingsSection.allCases) { s in
                    Label(s.label, systemImage: s.icon).tag(s)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.left").font(.body.weight(.semibold))
                            Text("Library")
                        }
                    }
                }
            }
        } detail: {
            NavigationStack {
                Group {
                    switch section ?? .editor {
                    case .editor: EditorSettings()
                    case .preview: PreviewSettings()
                    case .math: MathSettings()
                    case .export: ExportSettings()
                    case .about: AboutSettings()
                    }
                }
                .navigationTitle((section ?? .editor).label)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}

/// A − value + stepper row like the mockup's size controls.
@MainActor
struct SizeStepper: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>

    var body: some View {
        Stepper(value: $value, in: range, step: 1) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt").foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

@MainActor
struct EditorSettings: View {
    @EnvironmentObject var s: AppSettings

    var body: some View {
        Form {
            Section("Text") {
                HStack {
                    Text("Font")
                    Spacer()
                    Text("SF Mono").foregroundStyle(.secondary)
                }
                SizeStepper(title: "Size", value: $s.editorFontSize, range: 11...24)
                Picker("Line spacing", selection: $s.lineSpacing) {
                    ForEach(LineSpacing.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Typing") {
                Toggle("Highlight Markdown and math", isOn: $s.highlightSyntax)
                Toggle("Auto-close brackets and $", isOn: $s.autoPair)
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Smart quotes and dashes", isOn: $s.smartQuotes)
                    Text("Keep off: curly quotes break LaTeX.").font(.footnote).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Math keys under the editor", isOn: $s.mathKeys)
                    Text("$, $$, \\frac, ^, _, \\sqrt, align, cases, matrix").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Saving") {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Autosave", isOn: $s.autosave)
                    Text("Saves back to the original file in Files shortly after you stop typing.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Opening files") {
                Picker("Start in", selection: $s.defaultMode) {
                    ForEach(ViewMode.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

@MainActor
struct PreviewSettings: View {
    @EnvironmentObject var s: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $s.appearance) {
                    ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Match iPad follows Dark Mode in Control Center. Exported PDFs always use light colors.")
            }
            Section("Body font") {
                Picker("Body font", selection: $s.bodyFont) {
                    ForEach(BodyFont.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Reading") {
                SizeStepper(title: "Text size", value: $s.previewFontSize, range: 12...28)
                Toggle("Update while typing", isOn: $s.liveUpdate)
                Toggle("Highlight code blocks", isOn: $s.highlightCode)
            }
        }
    }
}

@MainActor
struct MathSettings: View {
    @EnvironmentObject var s: AppSettings

    var body: some View {
        Form {
            Section {
                TextEditor(text: $s.macros)
                    .font(.system(size: 14, design: .monospaced))
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .frame(minHeight: 140)
                Button("Restore default macros") { s.macros = AppSettings.defaultMacros }
            } header: {
                Text("Global macros")
            } footer: {
                Text("Loaded before every document. A \\newcommand inside a file overrides these.")
            }
            Section {
                Picker("Equation numbers", selection: $s.equationNumbers) {
                    ForEach(EquationNumbers.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Equation numbers")
            } footer: {
                Text(s.equationNumbers.hint)
            }
            Section("Recognized delimiters") {
                delimiterToggle("$ … $", "Inline math", $s.delimDollar)
                delimiterToggle("\\( … \\)", "Inline math", $s.delimParen)
                delimiterToggle("$$ … $$", "Display math", $s.delimDoubleDollar)
                delimiterToggle("\\[ … \\]", "Display math", $s.delimBracket)
            }
            Section("Errors") {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Show LaTeX errors in the preview", isOn: $s.showMathErrors)
                    Text("The broken formula appears in red with the reason.").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func delimiterToggle(_ code: String, _ label: String, _ on: Binding<Bool>) -> some View {
        Toggle(isOn: on) {
            HStack(spacing: 12) {
                Text(code).font(.system(.body, design: .monospaced)).foregroundStyle(Color.accentColor)
                Text(label).foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
struct ExportSettings: View {
    @EnvironmentObject var s: AppSettings

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Default format", selection: $s.exportFormat) {
                    ForEach(ExportFormat.allCases) { Text($0.label).tag($0) }
                }
                Picker("Paper size", selection: $s.paper) {
                    ForEach(Paper.allCases) { Text($0.label).tag($0) }
                }
                Picker("Margins", selection: $s.margins) {
                    ForEach(Margins.allCases) { Text($0.label).tag($0) }
                }
            }
            Section("Options") {
                Toggle("Page numbers in PDF", isOn: $s.pageNumbers)
                Toggle("Start each # heading on a new page", isOn: $s.headingPageBreak)
                Toggle("Use file name as document title", isOn: $s.fileNameAsTitle)
                Toggle("HTML follows the reader's Dark Mode", isOn: $s.htmlFollowsDarkMode)
            }
            Section {
                Toggle("Add today's date to the name", isOn: $s.dateInFileName)
            } header: {
                Text("File name")
            } footer: {
                Text("For example \"Gaussian integral 2026-10-25.pdf\". PDFs always use light colors so they print well.")
            }
        }
    }
}

@MainActor
struct AboutSettings: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image("Logo")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Text("Mappledown").font(.title2.weight(.bold))
                    Text("Version \(version)").foregroundStyle(.secondary)
                    Text("Open Markdown from Files, read it with real LaTeX math, make quick edits and export to PDF or HTML.")
                    HStack {
                        tag("Works offline")
                        tag("No account")
                        tag("Edits files in place")
                    }
                }
                .padding(.vertical, 8)
            }
            Section("Details") {
                row("Math rendering", "MathJax 3.2, bundled")
                row("Markdown", "markdown-it 14")
                row("Built with", "SwiftUI, no third-party Swift libraries")
                row("Requires", "iPadOS 16 or later")
                row("Installed with", "TrollStore (.ipa)")
            }
            Section("Open-source licenses") {
                Text("MathJax (Apache 2.0), markdown-it and markdown-it-footnote (MIT), highlight.js (BSD 3-Clause). Full license texts are inside the app bundle under Web/vendor.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("Source code on GitHub", destination: URL(string: "https://github.com/AccelerX/Mappledown")!)
            }
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
            Spacer()
            Text(v).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func tag(_ t: String) -> some View {
        Text(t)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
    }
}
