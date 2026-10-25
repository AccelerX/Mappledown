import SwiftUI
import UIKit

/// Lets the toolbar, math keys and status bar talk to the text view.
@MainActor
final class EditorController: ObservableObject {
    weak var textView: UITextView?
    @Published var line = 1
    @Published var column = 1

    /// Inserts `before` + selection + `after` and places the cursor `cursorBack` characters before the end.
    func insert(_ snippet: String, cursorBack: Int = 0) {
        guard let tv = textView, let range = tv.selectedTextRange else { return }
        tv.replace(range, withText: snippet)
        tv.delegate?.textViewDidChange?(tv)
        if cursorBack > 0, let end = tv.selectedTextRange?.end,
           let pos = tv.position(from: end, offset: -cursorBack) {
            tv.selectedTextRange = tv.textRange(from: pos, to: pos)
        }
        tv.becomeFirstResponder()
    }

    func undo() { textView?.undoManager?.undo() }
    func redo() { textView?.undoManager?.redo() }

    func updatePosition() {
        guard let tv = textView else { return }
        let text = tv.text as NSString
        let loc = min(tv.selectedRange.location, text.length)
        let before = text.substring(to: loc)
        let lines = before.components(separatedBy: "\n")
        line = lines.count
        column = (lines.last?.count ?? 0) + 1
    }
}

/// The Markdown source editor: a plain UITextView with light syntax colouring.
@MainActor
struct EditorView: UIViewRepresentable {
    @Binding var text: String
    @ObservedObject var settings: AppSettings
    var controller: EditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.spellCheckingType = .no
        tv.keyboardDismissMode = .interactive
        tv.alwaysBounceVertical = true
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 18, left: 16, bottom: 40, right: 16)
        tv.text = text
        controller.textView = tv
        context.coordinator.apply(settings: settings, to: tv)
        context.coordinator.highlight(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.parent = self
        controller.textView = tv
        if context.coordinator.appliedSignature != context.coordinator.signature(settings) {
            context.coordinator.apply(settings: settings, to: tv)
            context.coordinator.highlight(tv)
        }
        if tv.text != text {
            let selected = tv.selectedRange
            tv.text = text
            tv.selectedRange = NSRange(location: min(selected.location, (text as NSString).length), length: 0)
            context.coordinator.highlight(tv)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditorView
        var appliedSignature = ""
        private var highlightWork: DispatchWorkItem?

        init(_ parent: EditorView) { self.parent = parent }

        func signature(_ s: AppSettings) -> String {
            "\(s.editorFontSize)-\(s.lineSpacing.rawValue)-\(s.highlightSyntax)-\(s.smartQuotes)"
        }

        func apply(settings s: AppSettings, to tv: UITextView) {
            appliedSignature = signature(s)
            tv.smartQuotesType = s.smartQuotes ? .yes : .no
            tv.smartDashesType = s.smartQuotes ? .yes : .no
            tv.smartInsertDeleteType = .no
            tv.typingAttributes = baseAttributes(s)
        }

        func baseAttributes(_ s: AppSettings) -> [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = s.lineSpacing.extra
            return [
                .font: UIFont.monospacedSystemFont(ofSize: s.editorFontSize, weight: .regular),
                .foregroundColor: UIColor.editorBody,
                .paragraphStyle: para
            ]
        }

        // MARK: Colouring

        private static let rules: [(NSRegularExpression, Int)] = {
            func re(_ p: String, _ o: NSRegularExpression.Options = []) -> NSRegularExpression {
                // Patterns are fixed and tested; a failure here is a programming error.
                try! NSRegularExpression(pattern: p, options: o)
            }
            return [
                (re("^#{1,6}[ \\t].*$", [.anchorsMatchLines]), 1),                       // headings
                (re("\\\\begin\\{([A-Za-z*]+)\\}[\\s\\S]*?\\\\end\\{\\1\\}"), 2),         // environments
                (re("\\$\\$[\\s\\S]*?\\$\\$"), 2),                                         // $$ … $$
                (re("\\\\\\[[\\s\\S]*?\\\\\\]"), 2),                                       // \[ … \]
                (re("\\\\\\(.*?\\\\\\)"), 2),                                              // \( … \)
                (re("(?<![\\\\$])\\$(?!\\s)[^$\\n]+?(?<![\\s\\\\])\\$(?!\\d)"), 2),       // $ … $
                (re("^```[\\s\\S]*?^```", [.anchorsMatchLines]), 3),                     // code fences
                (re("`[^`\\n]+`"), 3)                                                     // inline code
            ]
        }()

        private static let delimiters: NSRegularExpression = {
            try! NSRegularExpression(pattern: "^#{1,6}|\\$\\$|\\$|\\\\[()\\[\\]]|\\\\(begin|end)\\{[A-Za-z*]+\\}", options: [.anchorsMatchLines])
        }()

        func highlight(_ tv: UITextView) {
            let s = parent.settings
            let storage = tv.textStorage
            let full = NSRange(location: 0, length: storage.length)
            let base = baseAttributes(s)
            let selected = tv.selectedRange
            storage.beginEditing()
            storage.setAttributes(base, range: full)
            if s.highlightSyntax && storage.length < 400_000 {
                let text = storage.string
                let boldFont = UIFont.monospacedSystemFont(ofSize: s.editorFontSize, weight: .semibold)
                for (re, kind) in Coordinator.rules {
                    re.enumerateMatches(in: text, range: full) { m, _, _ in
                        guard let r = m?.range else { return }
                        switch kind {
                        case 1:
                            storage.addAttributes([.font: boldFont, .foregroundColor: UIColor.label], range: r)
                        case 2:
                            storage.addAttribute(.foregroundColor, value: UIColor.editorMath, range: r)
                            Coordinator.delimiters.enumerateMatches(in: text, range: r) { d, _, _ in
                                if let dr = d?.range { storage.addAttribute(.foregroundColor, value: UIColor.tintColor, range: dr) }
                            }
                        default:
                            storage.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: r)
                        }
                    }
                }
                // Heading markers in the accent colour.
                let marks = try! NSRegularExpression(pattern: "^#{1,6}(?=[ \\t])", options: [.anchorsMatchLines])
                marks.enumerateMatches(in: text, range: full) { m, _, _ in
                    if let r = m?.range { storage.addAttribute(.foregroundColor, value: UIColor.tintColor, range: r) }
                }
            }
            storage.endEditing()
            tv.selectedRange = selected
            tv.typingAttributes = base
        }

        private func scheduleHighlight(_ tv: UITextView) {
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak tv] in
                guard let self, let tv, tv.markedTextRange == nil else { return }
                self.highlight(tv)
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }

        // MARK: UITextViewDelegate

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            parent.controller.updatePosition()
            scheduleHighlight(tv)
        }

        func textViewDidChangeSelection(_ tv: UITextView) {
            parent.controller.updatePosition()
        }

        private static let pairs: [String: String] = ["(": ")", "[": "]", "{": "}", "$": "$"]

        func textView(_ tv: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard parent.settings.autoPair, tv.markedTextRange == nil else { return true }
            let ns = tv.text as NSString
            let next: String? = range.location < ns.length ? ns.substring(with: NSRange(location: range.location, length: 1)) : nil

            // Typing a closer right before the same closer just steps over it.
            if range.length == 0, [")", "]", "}", "$"].contains(text), next == text {
                tv.selectedRange = NSRange(location: range.location + 1, length: 0)
                return false
            }
            guard let close = Coordinator.pairs[text], range.length == 0 else { return true }
            // Don't pair a backslash-escaped character.
            if range.location > 0, ns.substring(with: NSRange(location: range.location - 1, length: 1)) == "\\", text == "$" {
                return true
            }
            // Only pair when the next character is whitespace, a closer or the end.
            if let next, !(next == "\n" || next == " " || next == "\t" || [")", "]", "}", ",", "."].contains(next)) {
                return true
            }
            guard let start = tv.position(from: tv.beginningOfDocument, offset: range.location),
                  let end = tv.position(from: start, offset: range.length),
                  let textRange = tv.textRange(from: start, to: end) else { return true }
            tv.replace(textRange, withText: text + close)
            tv.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
            textViewDidChange(tv)
            return false
        }
    }
}

extension UIColor {
    static let editorBody = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.82, green: 0.82, blue: 0.84, alpha: 1) : UIColor(red: 0.23, green: 0.23, blue: 0.24, alpha: 1) }
    static let editorMath = UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.58, green: 0.77, blue: 0.99, alpha: 1) : UIColor(red: 0.12, green: 0.25, blue: 0.69, alpha: 1) }
}
