import SwiftUI

struct RegistersPane: View {
    let registers: [UInt32]
    let cpsr: UInt32
    let scale: UIScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneHeader(title: "Registers")
            // Seventeen fixed rows, so a ScrollView over a VStack rather than a
            // List — SKILL.md P1.4 asks for List when content is unbounded, and
            // List's row metrics pushed R10 onwards out of sight entirely.
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<16, id: \.self) { number in
                        register(Self.name(number),
                                 hex8(registers.indices.contains(number) ? registers[number] : 0))
                    }
                    Divider().padding(.vertical, 3)
                    register("CPSR", Self.flags(cpsr))
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func register(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
        }
        .font(scale.table)
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
    }

    /// R13/R14/R15 carry their architectural names, as µVision shows them.
    private static func name(_ number: Int) -> String {
        switch number {
        case 13: "R13 SP"
        case 14: "R14 LR"
        case 15: "R15 PC"
        default: "R\(number)"
        }
    }

    /// Spec §3: N, Z, C, V at bits 31–28. Shown as letters, since that is what
    /// a student needs to read after a CMP, not a hex word.
    private static func flags(_ cpsr: UInt32) -> String {
        let names = ["N", "Z", "C", "V"]
        let bits = [31, 30, 29, 28]
        return zip(names, bits)
            .map { cpsr & (1 << UInt32($1)) != 0 ? $0 : "-" }
            .joined()
    }
}

struct PaneHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5))
    }
}
