import AppKit
import SwiftUI

/// A plain-text code editor with a line-number gutter.
///
/// SwiftUI's `TextEditor` cannot show line numbers and offers no way to add them —
/// it exposes neither its layout manager nor its scroll view. The Debug view has
/// had a gutter since it was built, and the editor needs one for the same reason:
/// every diagnostic ARMd emits is reported as `line:column`, which is useless if
/// you cannot see which line you are on.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    let scale: UIScale

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = text

        // Assembly is not prose. Every one of these "helpful" substitutions corrupts
        // source: smart quotes break string literals and an em dash is not a minus.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isContinuousSpellCheckingEnabled = false

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let ruler = LineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.ruler = ruler

        apply(scale: scale, to: textView, ruler: ruler)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only when it actually differs: assigning `string` resets the insertion
        // point, so doing it on every update would fight the user's typing.
        if textView.string != text { textView.string = text }

        if let ruler = context.coordinator.ruler {
            apply(scale: scale, to: textView, ruler: ruler)
            ruler.needsDisplay = true
        }
    }

    /// Four columns, measured from the font rather than assumed. Whitespace is
    /// significant in ARMASM — column one is the label column — so a tab rendering
    /// eight wide here and four elsewhere misleads about the real layout.
    static func fourColumnStyle(for font: NSFont) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.tabStops = []
        style.defaultTabInterval = 4 * (" " as NSString).size(withAttributes: [.font: font]).width
        return style
    }

    private func apply(scale: UIScale, to textView: NSTextView, ruler: LineNumberRuler) {
        let body = NSFont.monospacedSystemFont(ofSize: scale.base, weight: .regular)
        if textView.font != body { textView.font = body }

        let style = CodeEditorView.fourColumnStyle(for: body)
        textView.defaultParagraphStyle = style
        textView.typingAttributes[.paragraphStyle] = style
        if let storage = textView.textStorage {
            storage.addAttribute(.paragraphStyle, value: style,
                                 range: NSRange(location: 0, length: storage.length))
        }
        ruler.font = NSFont.monospacedSystemFont(ofSize: max(9, scale.base - 3), weight: .regular)
        ruler.ruleThickness = max(34, scale.gutterWidth)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        weak var ruler: LineNumberRuler?

        init(_ parent: CodeEditorView) { self.parent = parent }

        /// Tab inserts spaces, never a tab character. A real tab leaves the label
        /// column at the mercy of whatever opens the file next — Keil, a lab PC, a
        /// diff — and in ARMASM that column decides whether a token is a label or an
        /// instruction.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.insertTab(_:)) else { return false }
            textView.insertText("    ", replacementRange: textView.selectedRange())
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            ruler?.needsDisplay = true
        }
    }
}

/// Draws one right-aligned number per line, for the lines currently on screen.
final class LineNumberRuler: NSRulerView {
    var font: NSFont = .monospacedSystemFont(ofSize: 10, weight: .regular)

    init(textView: NSTextView) {
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 34
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("LineNumberRuler is created in code only") }

    /// `NSRulerView`'s own drawing paints a border down the trailing edge, and it
    /// spans the full height of the enclosing scroll view — so it ran past the
    /// bottom of the text and bled into the debug bar beneath. Taking over `draw`
    /// entirely removes it; the gutter needs no rule, only its numbers.
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let content = textView.string as NSString
        let inset = textView.textContainerInset.height
        let visibleRect = scrollView?.contentView.bounds ?? .zero

        func drawNumber(_ number: Int, atLineStart glyphIndex: Int) {
            let lineRect = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: glyphIndex, length: 0), in: container
            )
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(
                at: NSPoint(x: ruleThickness - size.width - 6,
                            y: lineRect.minY + inset - visibleRect.minY),
                withAttributes: attributes
            )
        }

        guard content.length > 0 else {
            drawNumber(1, atLineStart: 0)
            return
        }

        let visibleGlyphs = layoutManager.glyphRange(forBoundingRect: visibleRect, in: container)
        let visibleChars = layoutManager.characterRange(forGlyphRange: visibleGlyphs,
                                                        actualGlyphRange: nil)

        // How many line breaks precede the first visible character.
        var number = 1
        content.enumerateSubstrings(
            in: NSRange(location: 0, length: visibleChars.location),
            options: [.byLines, .substringNotRequired]
        ) { _, _, _, _ in number += 1 }

        var index = visibleChars.location
        let end = NSMaxRange(visibleChars)
        while index <= end, index < content.length {
            let lineRange = content.lineRange(for: NSRange(location: index, length: 0))
            let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange,
                                                      actualCharacterRange: nil)
            drawNumber(number, atLineStart: glyphRange.location)
            number += 1

            // Every iteration must provably advance, or a zero-length range at the
            // end of the buffer spins here forever.
            let next = NSMaxRange(lineRange)
            guard next > index else { break }
            index = next
        }

        // A trailing newline means there is one more (empty) line to number, and it
        // has no characters for the loop above to have found.
        if content.hasSuffix("\n"), end >= content.length {
            drawNumber(number, atLineStart: layoutManager.numberOfGlyphs)
        }
    }
}
