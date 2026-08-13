import KeilAssembler
import SwiftUI

struct DebugBar: View {
    @Bindable var workspace: Workspace

    var body: some View {
        HStack(spacing: 10) {
            // Build lives here, not in the titlebar: this bar already owns running
            // and stepping, so the one control that starts a run belongs with them.
            Button {
                Task { await workspace.build() }
            } label: {
                Image(systemName: "hammer.fill")
            }
            .disabled(workspace.isBuilding)
            .keyboardShortcut("r", modifiers: .command)
            .help("Build & Run (⌘R)")

            if workspace.isBuilding {
                ProgressView().controlSize(.small)
            }

            Divider().frame(height: 14)

            Button {
                workspace.cursor -= 1
            } label: {
                Image(systemName: "backward.frame.fill")
            }
            .disabled(workspace.cursor <= 0)
            .keyboardShortcut("[", modifiers: .command)
            .help("Step Back (⌘[)")

            Button {
                workspace.cursor += 1
            } label: {
                Image(systemName: "forward.frame.fill")
            }
            .disabled(atEnd)
            .keyboardShortcut("]", modifiers: .command)
            .help("Step (⌘])")

            if workspace.snapshots.isEmpty {
                Text("No trace — press ⌘R")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("\(workspace.cursor + 1) / \(workspace.snapshots.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 62, alignment: .leading)

                TraceSlider(cursor: $workspace.cursor, count: workspace.snapshots.count)

                if let pc = workspace.currentSnapshot?.pc {
                    Text("PC \(hex8(pc))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.quaternary.opacity(0.35))
    }

    private var atEnd: Bool {
        workspace.snapshots.isEmpty || workspace.cursor >= workspace.snapshots.count - 1
    }
}

/// One tick per instruction, so the program's length and your position in it are
/// legible without reading the counter. Ticks are drawn only when they would be
/// more than two points apart — past that they read as noise, not information.
private struct TraceSlider: View {
    @Binding var cursor: Int
    let count: Int

    var body: some View {
        ZStack(alignment: .leading) {
            GeometryReader { proxy in
                if count > 1, proxy.size.width / CGFloat(count - 1) > 2 {
                    Path { path in
                        for step in 0..<count {
                            let x = proxy.size.width * CGFloat(step) / CGFloat(count - 1)
                            path.move(to: CGPoint(x: x, y: proxy.size.height / 2 - 3))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height / 2 + 3))
                        }
                    }
                    .stroke(.tertiary, lineWidth: 1)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(cursor) },
                    set: { cursor = Int($0.rounded()) }
                ),
                in: 0...Double(max(1, count - 1)),
                step: 1
            )
            .controlSize(.small)
        }
    }
}
