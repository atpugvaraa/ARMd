import AppKit
import SwiftUI

/// The sidebar's file list, as a real AppKit source list.
///
/// SwiftUI's `List` inside `NavigationSplitView` derives the sidebar's width from
/// its own row content, and then disagrees with the AppKit split view that actually
/// owns the column. Five attempts to reconcile the two failed: measured directly,
/// the rows were laid out against 400pt while the column drew at 260pt, so
/// `.truncationMode` fired to the wrong width and filenames spilled off the left
/// edge, taking the header and footer with them.
///
/// `NSTableView` has no such ambiguity. A single column under
/// `.uniformColumnAutoresizingStyle` is always exactly as wide as its enclosing
/// scroll view, and the cell's text field is pinned to both edges of that column —
/// so a filename physically cannot be wider than the space it has, and
/// `.byTruncatingMiddle` always has the correct width to truncate to.
struct SourceListView: NSViewRepresentable {
    let files: [URL]
    let selection: URL?
    /// The open document, when it has unsaved changes.
    let dirtyFile: URL?
    let onOpen: (URL) -> Void
    let onDelete: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.style = .sourceList
        table.headerView = nil
        // Xcode's navigator density — tighter than the system default, so the file
        // list reads of a piece with ARMd's register table rather than looser.
        table.rowHeight = 22
        table.allowsMultipleSelection = false
        table.backgroundColor = .clear
        table.delegate = context.coordinator
        table.dataSource = context.coordinator

        let column = NSTableColumn(identifier: .init("file"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        // The one line that makes this whole file worth it: the column tracks the
        // scroll view's width, so a cell is never wider than the space it has.
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        let menu = NSMenu()
        menu.delegate = context.coordinator
        // menuNeedsUpdate is authoritative; AppKit's own enabling would consult the
        // responder chain and disable everything.
        menu.autoenablesItems = false
        menu.addItem(withTitle: "Move to Trash",
                     action: #selector(Coordinator.moveClickedRowToTrash(_:)),
                     keyEquivalent: "").target = context.coordinator
        menu.addItem(.separator())
        menu.addItem(withTitle: "Reveal in Finder",
                     action: #selector(Coordinator.revealClickedRow(_:)),
                     keyEquivalent: "").target = context.coordinator
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false

        context.coordinator.table = table
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let table = context.coordinator.table else { return }
        table.reloadData()

        context.coordinator.withoutReportingSelection {
            if let selection, let row = files.firstIndex(of: selection) {
                if table.selectedRow != row {
                    table.selectRowIndexes([row], byExtendingSelection: false)
                }
            } else if table.selectedRow != -1 {
                table.deselectAll(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTableViewDelegate, NSTableViewDataSource, NSMenuDelegate {
        var parent: SourceListView
        weak var table: NSTableView?

        /// Set while this code is driving the selection, so the delegate callback
        /// does not mistake it for a click and re-open the file — which would
        /// bounce the unsaved-changes prompt back at the user on every redraw.
        private var applyingSelection = false

        init(_ parent: SourceListView) { self.parent = parent }

        func withoutReportingSelection(_ body: () -> Void) {
            applyingSelection = true
            body()
            applyingSelection = false
        }

        func numberOfRows(in tableView: NSTableView) -> Int { parent.files.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.files.count else { return nil }
            let cell = reusableCell(in: tableView)
            let url = parent.files[row]
            let isAssembly = ["s", "asm"].contains(url.pathExtension.lowercased())

            // The dot marks unsaved changes. Appending it to the string rather than
            // adding a second view keeps the cell to two subviews and one layout.
            cell.textField?.stringValue = url.lastPathComponent + (url == parent.dirtyFile ? "  •" : "")
            cell.textField?.toolTip = url.lastPathComponent
            cell.imageView?.image = NSImage(
                systemSymbolName: isAssembly ? "doc.text.fill" : "doc.text",
                accessibilityDescription: nil
            )
            cell.imageView?.contentTintColor = isAssembly ? .controlAccentColor : .secondaryLabelColor
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !applyingSelection, let table else { return }
            let row = table.selectedRow
            guard row >= 0, row < parent.files.count else { return }
            let url = parent.files[row]
            guard url != parent.selection else { return }
            parent.onOpen(url)
        }

        /// `clickedRow`, not `selectedRow` — right-clicking a row must act on that
        /// row, not on whatever file happens to be open.
        private var clickedURL: URL? {
            guard let table, table.clickedRow >= 0, table.clickedRow < parent.files.count
            else { return nil }
            return parent.files[table.clickedRow]
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            let enabled = clickedURL != nil
            for item in menu.items { item.isEnabled = enabled }
        }

        @objc func moveClickedRowToTrash(_ sender: Any?) {
            guard let url = clickedURL else { return }
            parent.onDelete(url)
        }

        @objc func revealClickedRow(_ sender: Any?) {
            guard let url = clickedURL else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }

        private func reusableCell(in tableView: NSTableView) -> NSTableCellView {
            let identifier = NSUserInterfaceItemIdentifier("ARMdFileCell")
            if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView {
                return existing
            }

            let cell = NSTableCellView()
            cell.identifier = identifier

            let icon = NSImageView()
            icon.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(icon)
            cell.imageView = icon

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingMiddle
            label.cell?.truncatesLastVisibleLine = true
            // Without this the label would rather push the column wider than lose a
            // character — which is the SwiftUI failure this file exists to avoid.
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            cell.addSubview(label)
            cell.textField = label

            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16),

                label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                // Pinned to the trailing edge: this is what forces truncation
                // instead of overflow.
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }
    }
}
