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
        .background(Color(nsColor: .underPageBackgroundColor))
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
            HStack(spacing: 8) {
                Button {
                    onNew()
                } label: {
                    Label("New File", systemImage: "plus")
                }
                Spacer(minLength: 4)
                Button {
                    onChooseFolder()
                } label: {
                    Label("Open Folder…", systemImage: "folder")
                }
            }
            .buttonStyle(.accessoryBar)
            .controlSize(.small)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .frame(height: 30)
        }
        .background(.bar)
    }
}
