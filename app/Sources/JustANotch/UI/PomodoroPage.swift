import SwiftUI

// Nút quay lại dùng chung cho các panel con của Timer.
func backButton(_ action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Image(systemName: "chevron.left")
            .font(.system(size: 11, weight: .bold)).foregroundStyle(.ink.opacity(0.8))
            .frame(width: 24, height: 24)
            .background(Circle().fill(.ink.opacity(0.1)))
    }
    .buttonStyle(.plain)
}
