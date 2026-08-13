import AppKit
import Foundation
import Observation

/// Asks — occasionally — whether the user wants to star the repository.
///
/// Deliberately quiet. It never appears on first launch, never before ARMd has
/// actually been useful, and never more than once a fortnight, and it can be turned
/// off for good in one click. A prompt that nags is a prompt people learn to
/// dismiss without reading, which is worse than not asking.
@Observable
@MainActor
final class StarPrompt {
    static let repository = URL(string: "https://github.com/atpugvaraa/ARMd")!

    private static let lastShownKey = "ARMdStarPromptLastShown"
    private static let declinedKey = "ARMdStarPromptDeclined"

    /// Three successful runs, so it only ever asks someone the app has worked for.
    private static let minimumBuilds = 3
    private static let interval: TimeInterval = 14 * 24 * 60 * 60

    var isPresented = false

    func consider(afterSuccessfulBuilds builds: Int) {
        guard builds >= Self.minimumBuilds else { return }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.declinedKey) else { return }

        let lastShown = defaults.double(forKey: Self.lastShownKey)
        let now = Date.timeIntervalSinceReferenceDate
        // Zero means it has never been shown, which is the one case that skips the
        // interval — otherwise the first prompt would wait a fortnight for nothing.
        guard lastShown == 0 || now - lastShown >= Self.interval else { return }

        defaults.set(now, forKey: Self.lastShownKey)
        isPresented = true
        PerfLog.info("showing star prompt after \(builds) successful builds")
    }

    func openRepository() {
        NSWorkspace.shared.open(Self.repository)
    }

    func declineForever() {
        UserDefaults.standard.set(true, forKey: Self.declinedKey)
    }
}
