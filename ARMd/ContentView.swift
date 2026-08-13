//
//  ContentView.swift
//  ARMd
//
//  Created by Aarav Gupta on 11/08/26.
//

import KeilAssembler
import SwiftUI

struct ContentView: View {
    let workspace: Workspace
    let store: FileStore
    let scale: UIScale
    @State private var showingPreload = false
    let showSidebar: Bool
    @Bindable var starPrompt: StarPrompt


    // HSplitView, not NavigationSplitView.
    //
    // NavigationSplitView keeps two disagreeing widths for its sidebar: the AppKit
    // split view's persisted width sizes the sidebar's hosting view, while
    // `.navigationSplitViewColumnWidth` draws the column at `ideal`. Measured — the
    // hosting view at 400pt, the column at 260pt — so the file list, folder header
    // and footer buttons were all laid out to 400 and clipped to 260, spilling off
    // the left edge. Removing the modifier renders the window blank; six attempts
    // to reconcile them failed.
    //
    // HSplitView has one width per pane and already resizes correctly for the
    // editor, inspector and console in this same window. The costs are the native
    // sidebar toggle and the sidebar material, both rebuilt below.
    var body: some View {
        SplitLayout(sidebarVisible: showSidebar,
                    minimumWidth: 170, defaultWidth: 210, maximumWidth: 420) {
                FileBrowser(
                    store: store,
                    selection: workspace.currentFile,
                    isDirty: workspace.isDirty,
                    onOpen: { workspace.open($0, using: store) },
                    onNew: { workspace.newFile(using: store) },
                    onChooseFolder: { store.chooseFolder() },
                    onDelete: { url in
                        // The open document is going to the Trash: keep the text in
                        // the buffer but forget the path, so the title reverts to
                        // Untitled and ⌘S asks where to put it.
                        if url == workspace.currentFile { workspace.forgetCurrentFile() }
                        store.moveToTrash(url)
                    }
                )
        } detail: {
            VSplitView {
                HSplitView {
                    VStack(spacing: 0) {
                        EditorPane(workspace: workspace, scale: scale)
                        Divider()
                        DebugBar(workspace: workspace)
                    }
                    .frame(minWidth: 380)

                    InspectorColumn(registers: workspace.registers,
                                    cpsr: workspace.currentSnapshot?.cpsr ?? 0,
                                    image: workspace.memory,
                                    scale: scale,
                                    changed: workspace.changedRegisters,
                                    cpsrChanged: workspace.cpsrChanged,
                                    onEditPreload: { showingPreload = true })
                }
                ConsolePane(text: workspace.consoleText,
                            diagnostics: workspace.diagnostics,
                            scale: scale)
                    .frame(minHeight: 120, idealHeight: 170)
            }
        }
        .navigationTitle(workspace.displayName)
        .navigationSubtitle(store.folderName)
        .sheet(isPresented: $showingPreload) {
            PreloadEditor(workspace: workspace)
        }
        .onChange(of: workspace.successfulBuilds) { _, builds in
            starPrompt.consider(afterSuccessfulBuilds: builds)
        }
        .alert("Enjoying ARMd?", isPresented: $starPrompt.isPresented) {
            Button("Star on GitHub") { starPrompt.openRepository() }
            Button("Not Now", role: .cancel) {}
            Button("Don't Ask Again") { starPrompt.declineForever() }
        } message: {
            Text("ARMd is free and open source. A star helps other students find it.")
        }
    }
}

#Preview {
    ContentView(workspace: Workspace(), store: FileStore(), scale: UIScale(),
                showSidebar: true, starPrompt: StarPrompt())
}

#Preview {
    ContentView(workspace: Workspace(), store: FileStore(), scale: UIScale(),
                showSidebar: true, starPrompt: StarPrompt())
}

/// The outer split's divider.
///
/// Pure SwiftUI, deliberately. An `NSViewRepresentable` here — even one reporting
/// a hard 6pt through `sizeThatFits` and `intrinsicContentSize` — stopped its
/// sibling `FileBrowser` from rendering at all, leaving an empty sidebar. Whatever
/// the interop cause, a representable does not belong as a sibling in this HStack.
///
/// `onContinuousHover` rather than `onHover` for the cursor: SwiftUI resets the
/// cursor as the pointer moves, so a one-shot `.set()` on entry gets undone.
/// Continuous hover fires on every movement and re-applies it.
private struct SidebarDivider: View {
    @Binding var width: Double
    let range: ClosedRange<Double>

    /// The width when the drag began — `DragGesture` reports translation from the
    /// gesture's start, so adding it to the live width each frame would accelerate.
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(width: 6)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active: NSCursor.resizeLeftRight.set()
                case .ended: NSCursor.arrow.set()
                @unknown default: NSCursor.arrow.set()
                }
            }
            .gesture(
                // minimumDistance 2: a bare click must not count as a resize.
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        let start = startWidth ?? width
                        if startWidth == nil { startWidth = start }
                        width = min(max(range.lowerBound, start + value.translation.width),
                                    range.upperBound)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}
