import SwiftUI

/// Two paw prints that "walk" in with a staggered fade — shown briefly near
/// the menu-bar icon on left-click.
struct PawStepView: View {
    @State private var step1 = false
    @State private var step2 = false

    var body: some View {
        ZStack {
            paw(rotation: -16, x: -18, y: 10, on: step1)
            paw(rotation: 14,  x: 12,  y: -8, on: step2)
        }
        .frame(width: 120, height: 64)
        .tint(.meetpaw)
        .onAppear {
            withAnimation(.easeOut(duration: 0.26)) { step1 = true }
            withAnimation(.easeOut(duration: 0.26).delay(0.14)) { step2 = true }
        }
    }

    private func paw(rotation: Double, x: CGFloat, y: CGFloat, on: Bool) -> some View {
        Image(systemName: "pawprint.fill")
            .font(.system(size: 28))
            .foregroundStyle(.tint)
            .rotationEffect(.degrees(rotation))
            .offset(x: x, y: on ? y : y + 10)   // settle upward as it fades in
            .opacity(on ? 1 : 0)
            .scaleEffect(on ? 1 : 0.7)
    }
}
