import Foundation
import KeilAssembler
import Observation

/// The one piece of mutable state the UI binds to. `@MainActor` because every
/// property drives a view; the build itself deliberately runs off the main actor.
@Observable
@MainActor
final class Workspace {
    var source: String = Workspace.starterProgram {
        didSet {
            guard source != oldValue else { return }
            isDirty = true
            // The trace was recorded from the previous text, so its highlighted line
            // and register values no longer describe what is on screen. Writing a
            // *different* property from this didSet is safe; assigning `source`
            // itself here would recurse (see `cursor`).
            if !snapshots.isEmpty { traceIsStale = true }
        }
    }

    /// Which half of the editor is showing. Before this existed, a successful build
    /// left the editor permanently read-only: the traced view appeared as soon as
    /// `snapshots` was non-empty and there was no way back to typing short of
    /// opening a different file.
    enum EditorMode { case edit, debug }
    var editorMode: EditorMode = .edit

    /// The source has been edited since the trace was recorded, so the trace
    /// describes text that no longer exists. The Debug tab stays available — a
    /// stale trace is still the best record of the last run — but it says so.
    private(set) var traceIsStale = false

    private(set) var snapshots: [MachineSnapshot] = []
    private(set) var diagnostics: [Diagnostic] = []
    private(set) var consoleText: String = ""
    private(set) var isBuilding = false

    private(set) var currentFile: URL?
    private(set) var isDirty = false

    var displayName: String { currentFile?.lastPathComponent ?? "Untitled" }

    /// The analysed program's data image folded with `preloadWords`, as of the
    /// last build (Spec §5.3). Empty before any build, and after a failed one.
    private(set) var initialMemory: [(address: UInt32, bytes: [UInt8])] = []

    /// Memory as of the cursor. A lab traces tens of instructions, so folding per
    /// cursor move is trivial; cache it keyed on the cursor if that stops being true.
    var memory: MemoryImage {
        MemoryImage.folding(initial: initialMemory, snapshots: snapshots, upTo: cursor)
    }

    private var clampedCursor = 0

    /// Index into `snapshots`, clamped on every write so no view can drive it out
    /// of range while a build replaces the trace underneath it.
    ///
    /// The clamp lives in a computed setter rather than a `didSet` on a stored
    /// property. `@Observable` rewrites a stored property into a computed accessor
    /// over a synthesised `_cursor`, so assigning `cursor` inside its own `didSet`
    /// re-enters the generated setter instead of being suppressed the way Swift
    /// suppresses it for a plain stored property — that recursed until the stack
    /// guard tripped, crashing the app on the first build.
    var cursor: Int {
        get { clampedCursor }
        set { clampedCursor = snapshots.isEmpty ? 0 : min(max(0, newValue), snapshots.count - 1) }
    }

    /// ARM7 memory the user typed in before running — Spec §5.3's preload image.
    var preloadWords: [UInt32: UInt32] = [:]

    var currentSnapshot: MachineSnapshot? {
        snapshots.indices.contains(cursor) ? snapshots[cursor] : nil
    }

    /// R0–R15 as of the cursor, or all zeros before a run.
    var registers: [UInt32] {
        currentSnapshot?.registers ?? [UInt32](repeating: 0, count: 16)
    }

    /// 0-based source line of the instruction at the cursor, for the editor highlight.
    var currentSourceLine: Int? { currentSnapshot?.sourceLine }

    func open(_ url: URL, using store: FileStore) {
        guard mayReplaceBuffer(using: store) else { return }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            consoleText = """
                \(url.lastPathComponent) could not be opened. \
                It may have been moved, renamed, or deleted outside ARMd.
                """
            PerfLog.error("could not read \(url.path)")
            // The important half: the row that just failed disappears instead of
            // sitting there to be clicked again.
            store.reload()
            return
        }
        source = text
        currentFile = url
        isDirty = false
        snapshots = []
        editorMode = .edit
        traceIsStale = false
        cursor = 0
        diagnostics = []
        consoleText = ""
        PerfLog.info("opened \(url.lastPathComponent)")
    }

    /// The skeleton a new document starts from. Distinct from `starterProgram`,
    /// which demonstrates three instructions; a new file should be a blank
    /// exercise, not someone else's answer — but it still carries the AREA/ENTRY/END
    /// boilerplate, which is pure ceremony a student should never have to recall.
    static let blankProgram = """
            AREA    PROGRAM, CODE, READONLY
            ENTRY

    MAIN

            END
    """

    /// True if it is safe to replace the current buffer.
    private func mayReplaceBuffer(using store: FileStore) -> Bool {
        guard isDirty else { return true }
        switch store.confirmDiscard(documentName: displayName) {
        case .discard: return true
        case .cancel: return false
        case .save:
            saveOrPrompt(using: store)
            // A cancelled Save panel leaves the document dirty — treat that as a
            // cancel too, rather than discarding the work the user just asked to keep.
            return !isDirty
        }
    }

    func newFile(using store: FileStore) {
        guard mayReplaceBuffer(using: store) else { return }
        source = Workspace.blankProgram
        currentFile = nil
        isDirty = false
        snapshots = []
        editorMode = .edit
        traceIsStale = false
        cursor = 0
        diagnostics = []
        consoleText = ""
        initialMemory = []
        PerfLog.info("new untitled document")
    }

    /// ⌘S. An untitled document asks where to go; a saved one just saves.
    func saveOrPrompt(using store: FileStore) {
        if currentFile == nil {
            guard let url = store.chooseSaveLocation(suggestedName: "Untitled.s") else { return }
            currentFile = url
        }
        try? save()
        // Make the file visible where the user just put it. Saving outside the open
        // folder otherwise looks like the file vanished.
        if let parent = currentFile?.deletingLastPathComponent(), parent != store.folder {
            store.openFolder(parent)
        } else {
            store.reload()
        }
    }

    /// The file behind this document is gone. Keep what the user typed — losing it
    /// because a file moved would be the worst possible response — but drop the path
    /// so ⌘S offers a Save panel instead of silently recreating the file.
    func forgetCurrentFile() {
        currentFile = nil
        isDirty = true
    }

    func save() throws {
        guard let currentFile else { return }
        try source.write(to: currentFile, atomically: true, encoding: .utf8)
        isDirty = false
        PerfLog.info("saved \(currentFile.lastPathComponent)")
    }

    func build() async {
        guard !isBuilding else { return }
        isBuilding = true
        defer { isBuilding = false }

        if isDirty, currentFile != nil { try? save() }

        PerfLog.mark("build-start")
        let source = self.source
        let preload = MemoryPreload(words: preloadWords)

        // Spec §7.9 spawns clang and then the built executable. Both block, so this
        // must not run on the main actor — SKILL.md P4.1.
        let outcome = await Task.detached { () -> Outcome in
            do {
                let result = try Driver().run(source: source, preload: preload, in: nil)
                return .ran(result)
            } catch {
                // A hard error (e.g. E020) stops `Driver.run` before it ever produces
                // a `RunResult`, but `Analyser` still recorded the diagnostic that
                // explains why. Recover it from the thrown failure so the
                // Diagnostics badge and ConsolePane's auto-switch (Task 7) have
                // something to react to — without this, every compile error looks
                // like an empty diagnostics list to the UI.
                let diagnostics: [Diagnostic]
                if case .compilationProducedNoAssembly(let diags) = error as? Driver.Failure {
                    diagnostics = diags
                } else {
                    diagnostics = []
                }
                return .failed(String(describing: error), diagnostics)
            }
        }.value

        switch outcome {
        case .ran(let result):
            snapshots = result.snapshots
            diagnostics = result.diagnostics
            initialMemory = result.initialMemory
            cursor = max(0, result.snapshots.count - 1)
            // A run that produced a trace is what the user pressed ⌘R to see.
            // A run that produced none has nothing to show, so stay in the editor.
            editorMode = result.snapshots.isEmpty ? .edit : .debug
            traceIsStale = false
            consoleText = Workspace.summary(of: result)
            PerfLog.info("build produced \(result.snapshots.count) snapshots, exit \(result.exitCode)")
        case .failed(let message, let diags):
            snapshots = []
            // The build failed: the user needs to fix the source, so put them back
            // where they can type.
            editorMode = .edit
            traceIsStale = false
            cursor = 0
            diagnostics = diags
            initialMemory = []
            consoleText = message
            PerfLog.error("build failed: \(message)")
        }
    }

    private enum Outcome: Sendable {
        case ran(RunResult)
        case failed(String, [Diagnostic])
    }

    private static func summary(of result: RunResult) -> String {
        var lines = ["exit code \(result.exitCode)", "\(result.snapshots.count) instructions traced"]
        if !result.standardError.isEmpty { lines.append(result.standardError) }
        for diagnostic in result.diagnostics {
            let severity = diagnostic.severity == .error ? "error" : "warning"
            lines.append("\(diagnostic.range.line + 1):\(diagnostic.range.column + 1) \(severity) \(diagnostic.code): \(diagnostic.message)")
        }
        return lines.joined(separator: "\n")
    }

    static let starterProgram = """
            AREA    PROGRAM, CODE, READONLY
            ENTRY

    MAIN
    MOV R1, #0X12
    MOV R2, R1
    MOV R3, R1
    END
    """
}
