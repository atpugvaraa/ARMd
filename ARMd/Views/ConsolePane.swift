import KeilAssembler
import SwiftUI

struct ConsolePane: View {
    let text: String
    let diagnostics: [Diagnostic]
    let scale: UIScale
    @State private var tab: Tab = .output

    enum Tab { case output, diagnostics }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                TabStripButton(title: "Output", isSelected: tab == .output) { tab = .output }
                TabStripButton(title: "Diagnostics",
                               isSelected: tab == .diagnostics,
                               badge: diagnostics.count) { tab = .diagnostics }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.5))

            Divider()

            switch tab {
            case .output: OutputPane(text: text, scale: scale)
            case .diagnostics: DiagnosticsPane(diagnostics: diagnostics, scale: scale)
            }
        }
        // Surface problems without stealing the strip when there are none.
        .onChange(of: errorCount) { _, count in
            if count > 0 { tab = .diagnostics }
        }
    }

    private var errorCount: Int {
        diagnostics.filter { $0.severity == .error }.count
    }
}
