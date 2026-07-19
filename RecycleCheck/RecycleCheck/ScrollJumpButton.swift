import SwiftUI

// MARK: - Общая плавающая кнопка перехода по странице

struct ScrollJumpButton: View {
    let isAtBottom: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isAtBottom ? "arrow.up" : "arrow.down")
                .font(.title)
                .fontWeight(.semibold)
                .foregroundStyle(tint)
                .frame(width: 60, height: 60)
                .animation(.easeInOut(duration: 0.2), value: isAtBottom)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(isAtBottom ? "Scroll to Top" : "Scroll to Bottom")
    }
}

#Preview {
    HStack(spacing: 24) {
        ScrollJumpButton(isAtBottom: false, tint: .purple) { }
        ScrollJumpButton(isAtBottom: true, tint: .green) { }
    }
    .padding()
}
