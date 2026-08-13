import KeilAssembler
import SwiftUI

struct InspectorColumn: View {
    let registers: [UInt32]
    let cpsr: UInt32
    let image: MemoryImage
    let scale: UIScale
    let onEditPreload: () -> Void

    var body: some View {
        VSplitView {
            // Seventeen rows at roughly 18pt plus the header need about 330pt.
            // At 240 the register file was clipped at R9.
            RegistersPane(registers: registers, cpsr: cpsr, scale: scale)
                .frame(minHeight: scale.registersMinHeight,
                       idealHeight: scale.registersMinHeight + 30)
            MemoryPane(image: image, scale: scale, onEditPreload: onEditPreload)
                .frame(minHeight: 120)
        }
        .frame(minWidth: 250, idealWidth: 280)
    }
}
