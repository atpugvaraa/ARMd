import AppKit
import SwiftUI

/// The window's outer split, as a real `NSSplitViewController`.
///
/// SwiftUI's containers could not do this job:
///
/// * `NavigationSplitView` keeps two disagreeing widths — the split view's
///   persisted width sizes the sidebar's hosting view while
///   `.navigationSplitViewColumnWidth` draws the column at `ideal` — so content
///   laid out at 400pt was clipped to 260pt and spilled off the left edge.
/// * `HSplitView` ignores `idealWidth` and opens a pane at its `minWidth` or
///   `maxWidth` depending on which sibling holds layout priority.
/// * A hand-rolled divider left a visible gap and dragged jitterily, and as an
///   `NSViewRepresentable` sibling it stopped `FileBrowser` rendering entirely.
///
/// `NSSplitViewController` is what AppKit sidebars actually use. It gives exact
/// minimum and maximum thickness, a genuine divider with the system resize cursor,
/// and autosaved divider positions. The representable is the window's root and both
/// panes live inside it, so there is no sibling for it to interfere with.
struct SplitLayout<Sidebar: View, Detail: View>: NSViewControllerRepresentable {
    let sidebarVisible: Bool
    let minimumWidth: CGFloat
    let defaultWidth: CGFloat
    let maximumWidth: CGFloat
    @ViewBuilder var sidebar: () -> Sidebar
    @ViewBuilder var detail: () -> Detail

    private static var autosaveName: String { "ARMdOuterSplit" }

    func makeCoordinator() -> SplitLayoutCoordinator { SplitLayoutCoordinator() }

    func makeNSViewController(context: Context) -> NSSplitViewController {
        let controller = NSSplitViewController()
        controller.splitView.isVertical = true
        controller.splitView.dividerStyle = .thin
        controller.splitView.autosaveName = Self.autosaveName

        let sidebarHost = NSHostingController(rootView: sidebar())
        let sidebarItem = NSSplitViewItem(viewController: sidebarHost)
        sidebarItem.minimumThickness = minimumWidth
        sidebarItem.maximumThickness = maximumWidth
        sidebarItem.canCollapse = true
        // The sidebar resists resizing and the detail absorbs it, which is what
        // keeps the sidebar at the width the user chose when the window resizes.
        sidebarItem.holdingPriority = NSLayoutConstraint.Priority(260)
        controller.addSplitViewItem(sidebarItem)

        let detailHost = NSHostingController(rootView: detail())
        let detailItem = NSSplitViewItem(viewController: detailHost)
        detailItem.minimumThickness = 640
        detailItem.holdingPriority = NSLayoutConstraint.Priority(250)
        controller.addSplitViewItem(detailItem)

        context.coordinator.sidebarHost = sidebarHost
        context.coordinator.detailHost = detailHost
        context.coordinator.sidebarItem = sidebarItem

        // Only on a machine that has never dragged this divider. Once AppKit has an
        // autosaved position, that is the user's choice and must win.
        let key = "NSSplitView Subview Frames \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil {
            DispatchQueue.main.async {
                controller.splitView.setPosition(defaultWidth, ofDividerAt: 0)
            }
        }

        return controller
    }

    func updateNSViewController(_ controller: NSSplitViewController, context: Context) {
        // Hosting controllers do not observe SwiftUI state on their own; handing
        // them a fresh root view on each update is what propagates changes.
        (context.coordinator.sidebarHost as? NSHostingController<Sidebar>)?.rootView = sidebar()
        (context.coordinator.detailHost as? NSHostingController<Detail>)?.rootView = detail()

        if let item = context.coordinator.sidebarItem, item.isCollapsed == sidebarVisible {
            item.animator().isCollapsed = !sidebarVisible
        }
    }

}

/// Top level and non-generic on purpose. Nested inside the generic `SplitLayout`
/// this crashed the Swift compiler — a segfault in the EarlyPerfInliner pass on
/// the class's deinit, with no diagnostic emitted. Hoisting it out of the generic
/// context avoids that entirely, and the panes are stored as plain
/// `NSViewController` so no generic parameter leaks in.
final class SplitLayoutCoordinator {
    var sidebarHost: NSViewController?
    var detailHost: NSViewController?
    var sidebarItem: NSSplitViewItem?
}
