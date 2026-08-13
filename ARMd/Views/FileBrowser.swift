import AppKit
import SwiftUI

struct FileBrowser: View {
    let store: FileStore
    let selection: URL?
    let isDirty: Bool
    let onOpen: (URL) -> Void
    let onNew: () -> Void
    let onChooseFolder: () -> Void
    let onDelete: (URL) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            if store.files.isEmpty {
                emptyState
            } else {
                // AppKit, deliberately — see SourceListView for why SwiftUI's List
                // could not be made to size correctly inside NavigationSplitView.
                SourceListView(
                    files: store.files,
                    selection: selection,
                    dirtyFile: isDirty ? selection : nil,
                    onOpen: onOpen,
                    onDelete: onDelete
                )
            }
            footer
        }
        // Xcode's navigator, not Finder's sidebar: a surface that sits a shade
        // behind the editor rather than one you can see the desktop through. Every
        // other surface in ARMd is opaque, and a single vibrant panel read as a
        // different application.
        .background(Color(nsColor: .windowBackgroundColor))
        .contextMenu {
            Button("New File") { onNew() }
            Button("Open Folder…") { onChooseFolder() }
            if let folder = store.folder {
                Divider()
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([folder])
                }
            }
        }
    }

    private var header: some View {
        Text(store.folderName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text(store.folder == nil ? "No folder open" : "No assembly files here")
                .font(.callout)
                .foregroundStyle(.secondary)
            if store.folder == nil {
                Text("Open a folder to get started.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Both actions are spelled out. The previous version was two bare glyphs whose
    /// meaning only arrived on a tooltip, seconds later — a button you have to hover
    /// to understand is a button that has not been labelled.
    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
            // The labelled version is what a first-time user needs, but pinning the
            // sidebar's minimum width to it kept the whole column wider than it had
            // to be. ViewThatFits keeps the words for as long as they fit and drops
            // to shorter ones — then to icons — only when the column is genuinely
            // narrow, so the floor can come down without losing the labels.
            ViewThatFits(in: .horizontal) {
                footerRow(newTitle: "New File", openTitle: "Open Folder…")
                ViewThatFits(in: .horizontal) {
                footerRow(newTitle: "New File", openTitle: "Open Folder…")
                footerRow(newTitle: "New", openTitle: "Open…")
                footerRow(newTitle: nil, openTitle: nil)
            }
                footerRow(newTitle: nil, openTitle: nil)
            }
            .buttonStyle(.accessoryBar)
            .controlSize(.small)
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
        .background(.bar)
    }

    /// `nil` titles give the icon-only fallback, which keeps its meaning through
    /// tooltips — acceptable as a last resort at a width where nothing else fits.
    private func footerRow(newTitle: String?, openTitle: String?) -> some View {
        HStack(spacing: 8) {
            Button(action: onNew) {
                label("plus", newTitle)
            }
            .help("New File (⌘N)")
            Spacer(minLength: 4)
            Button(action: onChooseFolder) {
                label("folder", openTitle)
            }
            .help("Open Folder… (⌘O)")
        }
        .lineLimit(1)
        .fixedSize()
    }

    @ViewBuilder
    private func label(_ symbol: String, _ title: String?) -> some View {
        if let title {
            Label(title, systemImage: symbol)
        } else {
            Image(systemName: symbol)
        }
    }
}
