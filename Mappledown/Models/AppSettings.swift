import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case edit, split, preview
    var id: String { rawValue }
    var label: String {
        switch self {
        case .edit: return "Edit"
        case .split: return "Split"
        case .preview: return "Preview"
        }
    }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match iPad"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
    /// nil means "follow the iPad".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum BodyFont: String, CaseIterable, Identifiable {
    case sans, serif
    var id: String { rawValue }
    var label: String { self == .sans ? "Sans serif" : "Serif" }
}

enum EquationNumbers: String, CaseIterable, Identifiable {
    case none, ams, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .ams: return "AMS (like LaTeX)"
        case .all: return "All displays"
        }
    }
    var hint: String {
        switch self {
        case .none: return "No numbers, even inside align or equation."
        case .ams: return "Numbers align and equation environments, like LaTeX. Use \\notag to skip one."
        case .all: return "Numbers every display equation, including $$…$$."
        }
    }
}

enum LineSpacing: String, CaseIterable, Identifiable {
    case compact, normal, relaxed
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Extra points between lines in the editor.
    var extra: CGFloat {
        switch self {
        case .compact: return 2
        case .normal: return 6
        case .relaxed: return 11
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable {
    case pdf, html
    var id: String { rawValue }
    var label: String { self == .pdf ? "PDF" : "HTML" }
    var fileExtension: String { rawValue }
}

enum Paper: String, CaseIterable, Identifiable {
    case a4, letter
    var id: String { rawValue }
    var label: String { self == .a4 ? "A4" : "US Letter" }
    /// Page size in PDF points (1/72 inch).
    var size: CGSize { self == .a4 ? CGSize(width: 595.2, height: 841.8) : CGSize(width: 612, height: 792) }
}

enum Margins: String, CaseIterable, Identifiable {
    case narrow, normal, wide
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var points: CGFloat {
        switch self {
        case .narrow: return 36
        case .normal: return 56
        case .wide: return 80
        }
    }
}

/// Every user setting, saved in UserDefaults as soon as it changes.
@MainActor
final class AppSettings: ObservableObject {
    static let defaultMacros = """
    \\newcommand{\\R}{\\mathbb R}
    \\newcommand{\\N}{\\mathbb N}
    \\newcommand{\\E}{\\mathbb E}
    \\newcommand{\\norm}[1]{\\left\\| #1 \\right\\|}
    \\DeclareMathOperator{\\tr}{tr}
    """

    private let store = UserDefaults.standard

    // Editor
    @Published var editorFontSize: Double { didSet { store.set(editorFontSize, forKey: "editorFontSize") } }
    @Published var lineSpacing: LineSpacing { didSet { store.set(lineSpacing.rawValue, forKey: "lineSpacing") } }
    @Published var highlightSyntax: Bool { didSet { store.set(highlightSyntax, forKey: "highlightSyntax") } }
    @Published var lineNumbers: Bool { didSet { store.set(lineNumbers, forKey: "lineNumbers") } }
    @Published var autoPair: Bool { didSet { store.set(autoPair, forKey: "autoPair") } }
    @Published var smartQuotes: Bool { didSet { store.set(smartQuotes, forKey: "smartQuotes") } }
    @Published var mathKeys: Bool { didSet { store.set(mathKeys, forKey: "mathKeys") } }
    @Published var autosave: Bool { didSet { store.set(autosave, forKey: "autosave") } }
    @Published var defaultMode: ViewMode { didSet { store.set(defaultMode.rawValue, forKey: "defaultMode") } }

    // Preview
    @Published var appearance: Appearance {
        didSet {
            store.set(appearance.rawValue, forKey: "appearance")
            applyAppearance()
        }
    }
    @Published var bodyFont: BodyFont { didSet { store.set(bodyFont.rawValue, forKey: "bodyFont") } }
    @Published var previewFontSize: Double { didSet { store.set(previewFontSize, forKey: "previewFontSize") } }
    @Published var liveUpdate: Bool { didSet { store.set(liveUpdate, forKey: "liveUpdate") } }
    @Published var syncScroll: Bool { didSet { store.set(syncScroll, forKey: "syncScroll") } }
    @Published var highlightCode: Bool { didSet { store.set(highlightCode, forKey: "highlightCode") } }

    // Math
    @Published var macros: String { didSet { store.set(macros, forKey: "macros") } }
    @Published var equationNumbers: EquationNumbers { didSet { store.set(equationNumbers.rawValue, forKey: "equationNumbers") } }
    @Published var delimDollar: Bool { didSet { store.set(delimDollar, forKey: "delimDollar") } }
    @Published var delimParen: Bool { didSet { store.set(delimParen, forKey: "delimParen") } }
    @Published var delimDoubleDollar: Bool { didSet { store.set(delimDoubleDollar, forKey: "delimDoubleDollar") } }
    @Published var delimBracket: Bool { didSet { store.set(delimBracket, forKey: "delimBracket") } }
    @Published var showMathErrors: Bool { didSet { store.set(showMathErrors, forKey: "showMathErrors") } }

    // Export
    @Published var exportFormat: ExportFormat { didSet { store.set(exportFormat.rawValue, forKey: "exportFormat") } }
    @Published var paper: Paper { didSet { store.set(paper.rawValue, forKey: "paper") } }
    @Published var margins: Margins { didSet { store.set(margins.rawValue, forKey: "margins") } }
    @Published var pageNumbers: Bool { didSet { store.set(pageNumbers, forKey: "pageNumbers") } }
    @Published var headingPageBreak: Bool { didSet { store.set(headingPageBreak, forKey: "headingPageBreak") } }
    @Published var tableOfContents: Bool { didSet { store.set(tableOfContents, forKey: "tableOfContents") } }
    @Published var fileNameAsTitle: Bool { didSet { store.set(fileNameAsTitle, forKey: "fileNameAsTitle") } }
    @Published var htmlFollowsDarkMode: Bool { didSet { store.set(htmlFollowsDarkMode, forKey: "htmlFollowsDarkMode") } }
    @Published var dateInFileName: Bool { didSet { store.set(dateInFileName, forKey: "dateInFileName") } }

    // Library
    @Published var showFilesTip: Bool { didSet { store.set(showFilesTip, forKey: "showFilesTip") } }

    init() {
        let d = UserDefaults.standard
        func bool(_ k: String, _ v: Bool) -> Bool { d.object(forKey: k) as? Bool ?? v }
        func double(_ k: String, _ v: Double) -> Double { d.object(forKey: k) as? Double ?? v }
        func pick<E: RawRepresentable>(_ k: String, _ v: E) -> E where E.RawValue == String {
            (d.string(forKey: k)).flatMap(E.init(rawValue:)) ?? v
        }

        editorFontSize = double("editorFontSize", 15)
        lineSpacing = pick("lineSpacing", LineSpacing.normal)
        highlightSyntax = bool("highlightSyntax", true)
        lineNumbers = bool("lineNumbers", true)
        autoPair = bool("autoPair", true)
        smartQuotes = bool("smartQuotes", false)
        mathKeys = bool("mathKeys", true)
        autosave = bool("autosave", true)
        defaultMode = pick("defaultMode", ViewMode.split)

        appearance = pick("appearance", Appearance.system)
        bodyFont = pick("bodyFont", BodyFont.sans)
        previewFontSize = double("previewFontSize", 17)
        liveUpdate = bool("liveUpdate", true)
        syncScroll = bool("syncScroll", true)
        highlightCode = bool("highlightCode", true)

        macros = d.string(forKey: "macros") ?? AppSettings.defaultMacros
        equationNumbers = pick("equationNumbers", EquationNumbers.ams)
        delimDollar = bool("delimDollar", true)
        delimParen = bool("delimParen", true)
        delimDoubleDollar = bool("delimDoubleDollar", true)
        delimBracket = bool("delimBracket", true)
        showMathErrors = bool("showMathErrors", true)

        exportFormat = pick("exportFormat", ExportFormat.pdf)
        paper = pick("paper", Paper.a4)
        margins = pick("margins", Margins.normal)
        pageNumbers = bool("pageNumbers", true)
        headingPageBreak = bool("headingPageBreak", false)
        tableOfContents = bool("tableOfContents", false)
        fileNameAsTitle = bool("fileNameAsTitle", true)
        htmlFollowsDarkMode = bool("htmlFollowsDarkMode", true)
        dateInFileName = bool("dateInFileName", false)

        showFilesTip = bool("showFilesTip", true)
    }

    /// Sets Light/Dark on every window, so sheets and full-screen screens follow too.
    /// (SwiftUI's preferredColorScheme can't switch back to "Match iPad" without a relaunch.)
    func applyAppearance() {
        let style: UIUserInterfaceStyle
        switch appearance {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows { window.overrideUserInterfaceStyle = style }
        }
    }

    /// What the preview page needs to know, sent to the web view as JSON.
    func renderConfig(dark: Bool) -> RenderConfig {
        RenderConfig(
            dollar: delimDollar,
            paren: delimParen,
            ddollar: delimDoubleDollar,
            bracket: delimBracket,
            tags: equationNumbers.rawValue,
            macros: macros,
            showErrors: showMathErrors,
            highlightCode: highlightCode,
            dark: dark,
            serif: bodyFont == .serif,
            fontSize: previewFontSize
        )
    }

    func previewIsDark(system: ColorScheme) -> Bool {
        switch appearance {
        case .system: return system == .dark
        case .light: return false
        case .dark: return true
        }
    }
}

/// Mirrors the option names in Resources/Web/render.js.
struct RenderConfig: Codable, Equatable {
    var dollar: Bool
    var paren: Bool
    var ddollar: Bool
    var bracket: Bool
    var tags: String
    var macros: String
    var showErrors: Bool
    var highlightCode: Bool
    var dark: Bool
    var serif: Bool
    var fontSize: Double
}
