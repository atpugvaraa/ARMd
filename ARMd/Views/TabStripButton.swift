import SwiftUI

/// One tab in a pane's tab strip. Shared by the console (Output / Diagnostics) and
/// the editor (Edit / Debug) so the two strips cannot drift apart.
struct TabStripButton: View {
    let title: String
    let isSelected: Bool
    var badge: Int = 0
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption2.monospacedDigit())
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.quaternary))
                }
            }
            .font(.caption.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? AnyShapeStyle(.selection) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
