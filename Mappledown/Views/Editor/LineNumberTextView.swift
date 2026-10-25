import UIKit

/// A UITextView (TextKit 1) with a line-number gutter on the left.
/// Numbers count source lines, so a long wrapped line keeps one number.
final class LineNumberTextView: UITextView {
    private let gutter = LineNumberGutter()
    private(set) var lineStarts: [Int] = [0]
    var baseInset = UIEdgeInsets(top: 18, left: 16, bottom: 40, right: 16) {
        didSet { updateInsets() }
    }

    var showsLineNumbers = true {
        didSet {
            gutter.isHidden = !showsLineNumbers
            updateInsets()
            setNeedsLayout()
        }
    }

    var numberFont: UIFont = .monospacedDigitSystemFont(ofSize: 12, weight: .regular) {
        didSet { gutter.setNeedsDisplay() }
    }

    init() {
        // Build the TextKit 1 stack ourselves: the gutter needs NSLayoutManager.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)
        gutter.textView = self
        gutter.isUserInteractionEnabled = false
        gutter.backgroundColor = .clear
        gutter.contentMode = .redraw
        addSubview(gutter)
        updateInsets()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var gutterWidth: CGFloat {
        guard showsLineNumbers else { return 0 }
        let digits = max(2, String(lineStarts.count).count)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: numberFont]).width
        return CGFloat(digits) * digitWidth + 22
    }

    /// Call after the text changes.
    func textDidChangeForGutter() {
        let old = lineStarts.count
        lineStarts = LineNumberTextView.computeLineStarts(text)
        if String(old).count != String(lineStarts.count).count { updateInsets() }
        gutter.setNeedsDisplay()
    }

    static func computeLineStarts(_ text: String) -> [Int] {
        var starts = [0]
        let ns = text as NSString
        let length = ns.length
        var i = 0
        while i < length {
            let r = ns.range(of: "\n", options: .literal, range: NSRange(location: i, length: length - i))
            if r.location == NSNotFound { break }
            starts.append(r.location + 1)
            i = r.location + 1
        }
        return starts
    }

    /// The 1-based source line that contains a character offset.
    func line(atOffset offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    /// The source line at the top edge of the visible area, with a fraction for how far it's scrolled past.
    func topVisibleLine() -> Double {
        let y = contentOffset.y + adjustedContentInset.top - textContainerInset.top
        let point = CGPoint(x: 0, y: max(0, y))
        let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyph)
        let line = self.line(atOffset: charIndex)
        let rect = rectForLine(line)
        let fraction = rect.height > 0 ? Double(min(max((y - rect.minY) / rect.height, 0), 1)) : 0
        return Double(line) + fraction
    }

    /// Scrolls so `line` (1-based, may be fractional) is at the top.
    func scroll(toLine line: Double) {
        let whole = max(1, min(Int(line), lineStarts.count))
        let rect = rectForLine(whole)
        let y = rect.minY + rect.height * CGFloat(line - Double(whole)) + textContainerInset.top - adjustedContentInset.top
        let maxY = max(0, contentSize.height - bounds.height + adjustedContentInset.bottom)
        setContentOffset(CGPoint(x: contentOffset.x, y: min(max(-adjustedContentInset.top, y), maxY)), animated: false)
    }

    /// The text-container rect covered by a whole source line (all its wrapped fragments).
    func rectForLine(_ line: Int) -> CGRect {
        let ns = text as NSString
        guard line >= 1, line <= lineStarts.count else { return .zero }
        let start = lineStarts[line - 1]
        let end = line < lineStarts.count ? lineStarts[line] : ns.length
        if start >= ns.length {
            return layoutManager.extraLineFragmentRect
        }
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: start, length: max(1, end - start)), actualCharacterRange: nil)
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    }

    private func updateInsets() {
        var inset = baseInset
        inset.left += gutterWidth
        textContainerInset = inset
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The gutter covers only the visible area and moves with scrolling.
        let frame = CGRect(x: 0, y: contentOffset.y, width: gutterWidth, height: bounds.height)
        if gutter.frame != frame {
            gutter.frame = frame
        }
        gutter.setNeedsDisplay()
    }
}

final class LineNumberGutter: UIView {
    weak var textView: LineNumberTextView?

    override func draw(_ rect: CGRect) {
        guard let tv = textView, tv.showsLineNumbers else { return }
        let lm = tv.layoutManager
        let inset = tv.textContainerInset
        let ns = tv.text as NSString

        // Separator line on the right edge.
        UIColor.separator.setFill()
        UIRectFill(CGRect(x: bounds.width - 1 / max(traitCollection.displayScale, 1) - 6, y: 0, width: 1 / max(traitCollection.displayScale, 1), height: bounds.height))

        let selected = tv.selectedRange.location
        let currentLine = tv.line(atOffset: min(selected, ns.length))
        let para = NSMutableParagraphStyle()
        para.alignment = .right
        let normal: [NSAttributedString.Key: Any] = [.font: tv.numberFont, .foregroundColor: UIColor.tertiaryLabel, .paragraphStyle: para]
        let current: [NSAttributedString.Key: Any] = [.font: tv.numberFont, .foregroundColor: UIColor.label, .paragraphStyle: para]

        // Visible area in text-container coordinates.
        let visible = CGRect(x: 0, y: tv.contentOffset.y - inset.top, width: tv.bounds.width, height: tv.bounds.height)
        let glyphRange = lm.glyphRange(forBoundingRect: visible, in: tv.textContainer)
        let numberWidth = bounds.width - 14

        func drawNumber(_ n: Int, fragment: CGRect) {
            let y = fragment.minY + inset.top - tv.contentOffset.y
            let h = tv.numberFont.lineHeight
            let bodyFont = (tv.typingAttributes[.font] as? UIFont) ?? tv.numberFont
            // Line the number's baseline up with the text's baseline.
            let baselineShift = bodyFont.ascender - tv.numberFont.ascender
            let r = CGRect(x: 0, y: y + baselineShift, width: numberWidth, height: h)
            ("\(n)" as NSString).draw(in: r, withAttributes: n == currentLine ? current : normal)
        }

        if glyphRange.length > 0 {
            let firstChar = lm.characterIndexForGlyph(at: glyphRange.location)
            var lineNumber = tv.line(atOffset: firstChar)
            var first = true
            lm.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, _, _, fragGlyphs, _ in
                let charIndex = lm.characterIndexForGlyph(at: fragGlyphs.location)
                let startsLine = charIndex == 0 || ns.character(at: charIndex - 1) == 10
                if startsLine {
                    if !first { lineNumber = tv.line(atOffset: charIndex) }
                    drawNumber(lineNumber, fragment: fragment)
                }
                first = false
            }
        }
        // The empty last line after a final newline.
        let extra = lm.extraLineFragmentRect
        if extra.height > 0, ns.length == 0 || ns.character(at: ns.length - 1) == 10 {
            drawNumber(tv.lineStarts.count, fragment: extra)
        }
    }
}
