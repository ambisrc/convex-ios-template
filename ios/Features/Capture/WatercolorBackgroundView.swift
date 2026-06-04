import SwiftUI

enum JournalPalette {
    static let ink = Color(red: 0.10, green: 0.15, blue: 0.13)
    static let secondaryInk = Color(red: 0.27, green: 0.36, blue: 0.32)
    static let moss = Color(red: 0.13, green: 0.33, blue: 0.27)
    static let teal = Color(red: 0.22, green: 0.68, blue: 0.72)
    static let paper = Color(red: 0.99, green: 0.97, blue: 0.91)
    static let warmCard = Color(red: 1.00, green: 0.99, blue: 0.95)
    static let sageCard = Color(red: 0.88, green: 0.94, blue: 0.90)
    static let peachCard = Color(red: 1.00, green: 0.94, blue: 0.86)
}

struct WatercolorBackgroundView: View {
    var fillsSafeArea = true

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.99, green: 0.96, blue: 0.88),
                    Color(red: 0.91, green: 0.96, blue: 0.89),
                    Color(red: 0.83, green: 0.93, blue: 0.94),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(Color(red: 0.40, green: 0.58, blue: 0.46).opacity(0.26))
                .frame(width: 250, height: 250)
                .blur(radius: 42)
                .offset(x: -150, y: -300)
            Circle()
                .fill(Color(red: 0.52, green: 0.78, blue: 0.82).opacity(0.28))
                .frame(width: 270, height: 270)
                .blur(radius: 46)
                .offset(x: 155, y: 240)
            Circle()
                .fill(Color(red: 0.94, green: 0.66, blue: 0.42).opacity(0.16))
                .frame(width: 220, height: 220)
                .blur(radius: 50)
                .offset(x: 130, y: -280)
            Rectangle()
                .fill(.white.opacity(0.08))
        }
        .modifier(SafeAreaFill(enabled: fillsSafeArea))
    }
}

private struct SafeAreaFill: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.ignoresSafeArea()
        } else {
            content
        }
    }
}
