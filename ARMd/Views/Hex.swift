import Foundation

/// `String(format:)` allocates nothing per call and needs no formatter object,
/// so these are safe to call from a view body — SKILL.md P3.1 is about
/// NumberFormatter and friends, not this.
func hex8(_ value: UInt32) -> String { String(format: "%08X", value) }
func hex4(_ value: UInt32) -> String { String(format: "%04X", value) }
