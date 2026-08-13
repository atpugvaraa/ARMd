import KeilAssembler
import SwiftUI

struct DiagnosticsPane: View {
    let diagnostics: [Diagnostic]
    let scale: UIScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if diagnostics.isEmpty {
                // ContentUnavailableView is sized for a window and swamps a 170pt
                // console pane — the same problem already fixed in MemoryPane.
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No diagnostics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    DiagnosticRow(diagnostic: diagnostic, scale: scale)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct DiagnosticRow: View {
    let diagnostic: Diagnostic
    let scale: UIScale

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: diagnostic.severity == .error
                  ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(diagnostic.code)  \(diagnostic.message)")
                    .font(scale.table)
                Text("line \(diagnostic.range.line + 1), column \(diagnostic.range.column + 1)")
                    .font(scale.caption)
                    .foregroundStyle(.secondary)
                if let note = diagnostic.note {
                    Text(note).font(scale.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
