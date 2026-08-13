import KeilAssembler
import SwiftUI

struct MemoryPane: View {
    let image: MemoryImage
    let scale: UIScale
    let onEditPreload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The preload editor sets memory values before a run, so it belongs on
            // the memory pane rather than in a corner of the titlebar.
            HStack(spacing: 0) {
                PaneHeader(title: "Memory")
                Button(action: onEditPreload) {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("Set memory values before running")
                .padding(.trailing, 8)
            }
            .background(.quaternary.opacity(0.5))
            let addresses = image.touchedWordAddresses
            if addresses.isEmpty {
                // ContentUnavailableView is sized for a window; at 260pt wide it
                // filled the pane with an icon and swallowed the inspector.
                VStack(spacing: 6) {
                    Image(systemName: "memorychip")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Text("No memory in use")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Lazy: a DCD block or a loop of stores reaches thousands of rows —
                // SKILL.md P1.4.
                List(addresses, id: \.self) { address in
                    LabeledContent(hex8(address)) {
                        Text(hex8(image.word(at: address)))
                    }
                    .font(scale.table)
                }
                .listStyle(.inset)
            }
        }
    }
}
