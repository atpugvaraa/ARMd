import SwiftUI

struct EditorPane: View {
    @Bindable var workspace: Workspace
    let scale: UIScale

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            content
        }
    }

    /// Edit and Debug are two views of the same file, so they get the same tab
    /// strip the console uses. Without it, a successful build left the editor
    /// read-only with no way back to typing.
    private var tabs: some View {
        HStack(spacing: 0) {
            TabStripButton(title: "Edit", isSelected: workspace.editorMode == .edit) {
                workspace.editorMode = .edit
            }
            TabStripButton(title: "Debug",
                           isSelected: workspace.editorMode == .debug,
                           isEnabled: !workspace.snapshots.isEmpty) {
                workspace.editorMode = .debug
            }
            Spacer()
            if workspace.traceIsStale {
                // The trace was recorded from text that has since changed, so the
                // highlighted line and the register values describe a program that
                // no longer exists. Say so rather than letting it quietly mislead.
                Label("Edited since last run — ⌘R", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.trailing, 8)
            } else if isDebugging {
                Text("Read-only")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.5))
    }

    /// Debug needs a trace to show. Asking for it without one falls back to the
    /// editor rather than presenting an empty pane.
    private var isDebugging: Bool {
        workspace.editorMode == .debug && !workspace.snapshots.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if isDebugging {
            TracedSource(lines: workspace.source.components(separatedBy: "\n"),
                         highlighted: workspace.currentSourceLine,
                         scale: scale)
        } else {
            // AppKit, for the line-number gutter — see CodeEditorView.
            CodeEditorView(text: $workspace.source, scale: scale)
                .background(.background)
        }
    }
}

private struct TracedSource: View {
    let lines: [String]
    let highlighted: Int?
    let scale: UIScale

    var body: some View {
        ScrollViewReader { proxy in
            // A lab program is tens of lines, but List is lazy and costs nothing
            // extra here — SKILL.md P1.4.
            List(Array(lines.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1)")
                        .font(scale.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: scale.gutterWidth, alignment: .trailing)
                    Text(text.isEmpty ? " " : text)
                        .font(scale.code)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(index == highlighted ? Color.accentColor.opacity(0.22) : Color.clear)
                .id(index)
            }
            .listStyle(.plain)
            .onChange(of: highlighted) { _, line in
                guard let line else { return }
                withAnimation { proxy.scrollTo(line, anchor: .center) }
            }
        }
    }
}
