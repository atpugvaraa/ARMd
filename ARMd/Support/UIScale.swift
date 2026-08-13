import SwiftUI

/// How large the text a user reads should be. Chrome — sidebar, toolbar, debug bar,
/// console tabs — keeps system metrics and is deliberately not scaled: navigation
/// that grows with the content is what makes a window feel broken.
struct UIScale: Equatable {
    static let defaultBase: Double = 13
    static let range: ClosedRange<Double> = 9...28

    /// Point size for source code. Everything else is derived from it.
    var base: Double

    init(base: Double = UIScale.defaultBase) {
        self.base = min(max(base, UIScale.range.lowerBound), UIScale.range.upperBound)
    }

    /// Source text, and anything else read as code.
    var code: Font { .system(size: base, design: .monospaced) }

    /// Machine-state tables — registers, memory. Denser than code on purpose;
    /// these are scanned, not read.
    var table: Font { .system(size: max(9, base - 2), design: .monospaced) }

    /// Line numbers and secondary labels.
    var caption: Font { .system(size: max(8, base - 3), design: .monospaced) }

    /// The editor's line-number gutter, wide enough for four digits at any size.
    var gutterWidth: CGFloat { base * 2.6 }

    /// Seventeen register rows plus the pane header. Derived rather than fixed: at
    /// 13pt this is the 330 that used to be hard-coded, and at larger sizes it keeps
    /// the whole register file visible instead of forcing a scroll from the start.
    var registersMinHeight: CGFloat { max(330, base * 26) }
}
