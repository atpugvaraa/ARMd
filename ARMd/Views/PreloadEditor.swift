import SwiftUI

struct PreloadEditor: View {
    @Bindable var workspace: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var addressText = ""
    @State private var valueText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Memory Preload").font(.headline)
            Text("Values written into ARM7 memory before the program runs.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                TextField("Address", text: $addressText, prompt: Text("00001000")).monospaced()
                TextField("Value", text: $valueText, prompt: Text("00000012")).monospaced()
                Button("Add") { add() }.disabled(parsed == nil)
            }
            .textFieldStyle(.roundedBorder)

            if workspace.preloadWords.isEmpty {
                Text("None.").font(.caption).foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(workspace.preloadWords.keys.sorted(), id: \.self) { address in
                        LabeledContent(hex8(address)) {
                            HStack {
                                Text(hex8(workspace.preloadWords[address] ?? 0)).monospaced()
                                Button {
                                    workspace.preloadWords[address] = nil
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .monospaced()
                    }
                }
                .frame(minHeight: 130)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    /// Hex, with or without a leading 0x or & — the lab writes it both ways.
    private var parsed: (UInt32, UInt32)? {
        func value(_ text: String) -> UInt32? {
            let cleaned = text.trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "&", with: "")
            guard !cleaned.isEmpty, let parsed = UInt32(cleaned, radix: 16) else { return nil }
            return parsed
        }
        guard let address = value(addressText), let word = value(valueText) else { return nil }
        return (address, word)
    }

    private func add() {
        guard let (address, word) = parsed else { return }
        workspace.preloadWords[address] = word
        addressText = ""
        valueText = ""
    }
}
