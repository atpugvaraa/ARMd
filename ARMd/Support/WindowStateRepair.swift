import AppKit
import Foundation

/// SwiftUI persists a `NavigationSplitView`'s column widths as raw `NSSplitView`
/// subview frames, and restores them verbatim without refitting them to the window
/// they are being restored into. Drag the divider while the window is wide, then
/// reopen it narrower — or on a smaller display — and the restored frames can total
/// far more than the window is wide. The sidebar is then laid out at its old width
/// with a negative origin, and its contents spill off the left edge: rows clipped
/// mid-filename, the section header and the bottom bar gone entirely.
///
/// Observed here: subviews of 428pt and 1915pt restored into a 1562pt window.
///
/// AppKit offers no way to ask it to refit them, so the stale entry is dropped
/// before the window is built. Forgetting a divider position costs the user one
/// drag; the alternative is an app that looks broken and a student running
/// `defaults delete` to fix it.
enum WindowStateRepair {
    private static let splitPrefix = "NSSplitView Subview Frames "
    private static let windowPrefix = "NSWindow Frame "

    static func dropOversizedSplitFrames() {
        let defaults = UserDefaults.standard
        let everything = defaults.dictionaryRepresentation()

        for (key, value) in everything where key.hasPrefix(splitPrefix) {
            guard let frames = value as? [String] else { continue }

            let total = frames.reduce(0.0) { running, frame in
                running + (width(ofSplitFrame: frame) ?? 0)
            }
            guard total > 0, let available = windowWidth(forSplitKey: key, in: everything) else { continue }

            // A 1pt allowance: AppKit rounds, and an exact match is not the point.
            if total > available + 1 {
                PerfLog.info("dropping inconsistent split geometry: \(Int(total))pt of panes in a \(Int(available))pt window")
                defaults.removeObject(forKey: key)
            }
        }
    }

    /// Each entry is "x, y, width, height, collapsed, hidden".
    private static func width(ofSplitFrame frame: String) -> Double? {
        let fields = frame.split(separator: ",")
        guard fields.count > 2 else { return nil }
        return Double(fields[2].trimmingCharacters(in: .whitespaces))
    }

    /// The split key is `NSSplitView Subview Frames <id>, SidebarNavigationSplitView`
    /// and its window is `NSWindow Frame <id>`, whose value is "x y w h …".
    /// Pairing them is what makes the check meaningful: the pane widths have to fit
    /// the window they will be restored into, not merely the screen.
    private static func windowWidth(forSplitKey key: String, in defaults: [String: Any]) -> Double? {
        var identifier = String(key.dropFirst(splitPrefix.count))
        if let comma = identifier.range(of: ", ", options: .backwards) {
            identifier = String(identifier[identifier.startIndex..<comma.lowerBound])
        }
        guard let frame = defaults[windowPrefix + identifier] as? String else { return nil }
        let fields = frame.split(separator: " ")
        guard fields.count > 2 else { return nil }
        return Double(fields[2])
    }
}
