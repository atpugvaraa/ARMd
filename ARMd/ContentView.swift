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
        HSplitView {
            if showSidebar {
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
                // 220, not 180: the footer carries two labelled buttons under
                // `.fixedSize()`, so it never compresses below ~180pt. A minimum at
                // that boundary let the sidebar be dragged until those buttons
                // clipped — the unlabelled-glyph problem returning by another route.
                .frame(minWidth: 220, idealWidth: 260, maxWidth: 460)
            }

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
                                    onEditPreload: { showingPreload = true })
                }
                ConsolePane(text: workspace.consoleText,
                            diagnostics: workspace.diagnostics,
                            scale: scale)
                    .frame(minHeight: 120, idealHeight: 170)
            }
            .frame(minWidth: 640)
        }
        .navigationTitle(workspace.displayName)
        .navigationSubtitle(store.folderName)
        .sheet(isPresented: $showingPreload) {
            PreloadEditor(workspace: workspace)
        }
    }
}

#Preview {
    ContentView(workspace: Workspace(), store: FileStore(), scale: UIScale(), showSidebar: true)
}
