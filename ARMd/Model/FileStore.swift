import AppKit
import Foundation
import Observation

/// The folder of lab exercises shown in the sidebar. Lab files stay ordinary
/// files on disk so Finder, a mail attachment, or the lab PC can read them too.
@Observable
@MainActor
final class FileStore {
    private(set) var folder: URL?
    private(set) var files: [URL] = []

    private static let bookmarkKey = "ARMdLastFolderBookmark"

    init() { restoreLastFolder() }

    var folderName: String { folder?.lastPathComponent ?? "No Folder" }

    /// The app sandbox is off, so a plain path bookmark is enough — no
    /// security scope to start or stop.
    func openFolder(_ url: URL) {
        folder = url
        UserDefaults.standard.set(url.path, forKey: Self.bookmarkKey)
        reload()
        watchFolder()
        PerfLog.info("opened folder \(url.lastPathComponent)")
    }

    private var watcher: DispatchSourceFileSystemObject?

    /// Files arrive and vanish behind the app's back — a student deletes one in
    /// Finder, or unzips a fresh set of exercises. Without this the sidebar keeps
    /// showing rows for files that are gone, and clicking one produced nothing but
    /// "Could not read …".
    private func watchFolder() {
        watcher?.cancel()
        watcher = nil
        guard let folder else { return }

        // `Darwin.open`, qualified: unqualified `open` resolves to this class's own
        // folder-opening method.
        let descriptor = Darwin.open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            PerfLog.error("could not watch \(folder.path)")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.reload() }
        }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
        watcher = source
    }

    // No deinit: `watcher` is @MainActor-isolated and deinit is not, and this store
    // is created once in ARMdApp and lives as long as the app does. The source's
    // cancel handler closes the descriptor when a new folder replaces the old one,
    // which is the only case that actually occurs.

    /// Move to Trash, never delete. A student who trashes the wrong lab file has to
    /// be able to get it back.
    func moveToTrash(_ url: URL) {
        NSWorkspace.shared.recycle([url]) { _, error in
            if let error { PerfLog.error("could not trash \(url.path): \(error)") }
        }
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url { openFolder(url) }
    }

    func reload() {
        guard let folder else { files = []; return }
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []
        files = contents
            .filter { ["s", "asm", "txt"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private func restoreLastFolder() {
        guard let path = UserDefaults.standard.string(forKey: Self.bookmarkKey) else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        folder = url
        reload()
        watchFolder()
    }

    /// Where to save an untitled document. Deliberately does not set
    /// `allowedContentTypes` — the lab uses `.s`, `.asm` and occasionally `.txt`,
    /// and a content-type filter would fight a student typing any of the other two.
    func chooseSaveLocation(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.directoryURL = folder
        panel.prompt = "Save"
        return panel.runModal() == .OK ? panel.url : nil
    }

    enum SaveDecision { case save, discard, cancel }

    /// The standard macOS three-button question, asked before anything replaces an
    /// edited buffer. Without it, opening another file silently discards work —
    /// which it has always done, and which ⌘N would otherwise inherit.
    func confirmDiscard(documentName: String) -> SaveDecision {
        let alert = NSAlert()
        alert.messageText = "Save changes to \(documentName)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertSecondButtonReturn: return .discard
        default: return .cancel
        }
    }
}
