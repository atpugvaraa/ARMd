//
//  ARMdApp.swift
//  ARMd
//
//  Created by Aarav Gupta on 11/08/26.
//

import SwiftUI

@main
struct ARMdApp: App {
    @State private var workspace = Workspace()
    @State private var store = FileStore()
    @State private var toolchain = Toolchain()
    @State private var starPrompt = StarPrompt()
    @AppStorage("uiFontSize") private var fontSize = UIScale.defaultBase
    /// Lives here rather than in ContentView so the View menu can drive it — and,
    /// unlike the toolbar button it replaces, the choice survives a relaunch.
    @AppStorage("showSidebar") private var showSidebar = true

    init() {
        // Before any window exists — a restored split geometry that no longer fits
        // its window makes the sidebar spill off the left edge.
        WindowStateRepair.dropOversizedSplitFrames()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(workspace: workspace, store: store,
                        scale: UIScale(base: fontSize), showSidebar: showSidebar,
                        starPrompt: starPrompt)
                .frame(minWidth: 980, minHeight: 600)
                .task { await toolchain.check() }
                .sheet(isPresented: .constant(toolchain.needsSetup)) {
                    OnboardingSheet(toolchain: toolchain)
                }
                .interactiveDismissDisabled()
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") { workspace.newFile(using: store) }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Open Folder…") { store.chooseFolder() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                // Live whenever the document is dirty *or* has never been saved, so a
                // fresh ⌘N document can reach disk immediately. The old condition
                // required an existing file, which left an untitled document unsavable.
                Button("Save") { workspace.saveOrPrompt(using: store) }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!workspace.isDirty && workspace.currentFile != nil)
            }
            // Routing the arithmetic through UIScale(base:) keeps the 9–28 clamp in
            // exactly one place, so no menu item can drive the value out of range.
            CommandGroup(replacing: .help) {
                Button("ARMd on GitHub") { starPrompt.openRepository() }
            }
            CommandGroup(after: .sidebar) {
                Button(showSidebar ? "Hide Sidebar" : "Show Sidebar") { showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Divider()
                Button("Increase Text Size") { fontSize = UIScale(base: fontSize + 1).base }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Decrease Text Size") { fontSize = UIScale(base: fontSize - 1).base }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { fontSize = UIScale.defaultBase }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
