import Foundation
import KeilAssembler
import Observation

/// Whether this Mac can build ARM7 programs, and the one action that fixes it if
/// it can't. Checked at launch so a student meets a sentence and a button rather
/// than a compiler error.
@Observable
@MainActor
final class Toolchain {
    /// `nil` until the first check finishes, so the sheet cannot flash on a machine
    /// that was fine all along.
    private(set) var status: ToolchainStatus?
    private(set) var isInstalling = false
    /// Set when macOS reports the tools are already installed but they still do not
    /// work — the one case the automatic route cannot fix on its own.
    private(set) var manualStepsNeeded = false

    var needsSetup: Bool {
        if case .missing = status { return true }
        return false
    }

    func check() async {
        // Compiling blocks; SKILL.md P4.1.
        let result = await Task.detached { Driver().preflight() }.value
        status = result
        PerfLog.info("toolchain \(result == .ready ? "ready" : "missing")")
    }

    /// Raises Apple's own Command Line Tools installer and waits for it. A silent
    /// install needs admin rights and consent this app cannot fake, so summoning
    /// the system installer is the whole of what an app is allowed to do — the
    /// part worth automating is noticing when it finishes.
    func install() async {
        isInstalling = true
        manualStepsNeeded = false
        defer { isInstalling = false }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        process.arguments = ["--install"]
        do {
            try process.run()
            process.waitUntilExit()
            // Nonzero here means macOS believes the tools are already present.
            // Since preflight just proved they don't work, the install route is
            // exhausted and the student needs the manual fallback.
            if process.terminationStatus != 0 {
                await check()
                if status != .ready { manualStepsNeeded = true; return }
            }
        } catch {
            PerfLog.error("xcode-select --install failed: \(error)")
            manualStepsNeeded = true
            return
        }

        // `xcode-select --install` returns as soon as the installer is on screen;
        // the download itself finishes minutes later in a separate process. The
        // only reliable completion signal is the thing we actually care about.
        for _ in 0..<600 {
            try? await Task.sleep(for: .seconds(3))
            await check()
            if status == .ready { return }
        }
        manualStepsNeeded = true
    }
}
