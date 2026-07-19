import SwiftUI

// MARK: - Общая плавающая кнопка перехода по странице

struct ScrollJumpButton: View {
    let isAtBottom: Bool
    let tint: Color
    let visualOpacity: Double
    let action: () -> Void

    init(
        isAtBottom: Bool,
        tint: Color,
        visualOpacity: Double = 1,
        action: @escaping () -> Void
    ) {
        self.isAtBottom = isAtBottom
        self.tint = tint
        self.visualOpacity = visualOpacity
        self.action = action
    }

    var body: some View {
        Group {
            if visualOpacity < 1 {
                Button(action: action) {
                    icon
                        .glassEffect(.regular.interactive(), in: Circle())
                        .opacity(visualOpacity)
                }
                .buttonStyle(.plain)
                .contentShape(Circle())
            } else {
                Button(action: action) {
                    icon
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
        .accessibilityLabel(isAtBottom ? "Scroll to Top" : "Scroll to Bottom")
    }

    private var icon: some View {
        Image(systemName: isAtBottom ? "arrow.up" : "arrow.down")
            .font(.title)
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(width: 60, height: 60)
            .animation(.easeInOut(duration: 0.2), value: isAtBottom)
    }
}

#Preview {
    HStack(spacing: 24) {
        ScrollJumpButton(isAtBottom: false, tint: .purple) { }
        ScrollJumpButton(isAtBottom: true, tint: .green) { }
    }
    .padding()
}
