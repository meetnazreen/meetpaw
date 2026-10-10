import SwiftUI
import AppKit

/// Swipe a row right-to-left to reveal a red Delete button (macOS has no
/// native swipeActions). Fires haptic feedback on reveal and on delete.
struct SwipeToDelete<Content: View>: View {
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var offset: CGFloat = 0
    @State private var hapticArmed = true
    private let deleteWidth: CGFloat = 76
    private let rowHeight: CGFloat = 46

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            HStack(spacing: 0) {
                content.frame(width: w, height: rowHeight)
                Button(action: performDelete) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.white)
                        .frame(width: deleteWidth, height: rowHeight)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
            }
            .offset(x: offset)
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        let t = min(0, max(-deleteWidth, value.translation.width))
                        offset = t
                        if t <= -deleteWidth * 0.6, hapticArmed {   // crossed open threshold
                            haptic(); hapticArmed = false
                        } else if t > -deleteWidth * 0.6 {
                            hapticArmed = true
                        }
                    }
                    .onEnded { value in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = value.translation.width <= -deleteWidth * 0.5 ? -deleteWidth : 0
                        }
                    }
            )
        }
        .frame(height: rowHeight)
        .clipped()
    }

    private func performDelete() {
        haptic()
        withAnimation(.easeInOut(duration: 0.2)) { offset = 0 }
        onDelete()
    }

    private func haptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
