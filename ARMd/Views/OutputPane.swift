import SwiftUI

struct OutputPane: View {
    let text: String
    let scale: UIScale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                Text(text.isEmpty ? "Press ⌘R to build and run." : text)
                    .font(scale.table)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }
}
