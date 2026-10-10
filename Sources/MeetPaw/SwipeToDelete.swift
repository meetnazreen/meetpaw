import SwiftUI
import AppKit

/// Swipe a row right-to-left (trackpad two-finger swipe) to reveal a red Delete
/// button. Vertical scrolls pass through to the list. Haptics on reveal/delete.
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
                SwipeCatcher(onScroll: handle) {
                    content
                        .frame(width: w, height: rowHeight)
                        // Right-click fallback for a regular mouse (no swipe).
                        .contextMenu {
                            Button(role: .destructive, action: onDelete) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .frame(width: w, height: rowHeight)
                Button(action: performDelete) {
                    Image(systemName: "trash.fill")
                        .foregroundStyle(.white)
                        .frame(width: deleteWidth, height: rowHeight)
                        .background(Color.red)
                }
                .buttonStyle(.plain)
            }
            .offset(x: offset)
        }
        .frame(height: rowHeight)
        .clipped()
    }

    private func handle(_ delta: CGFloat, _ ended: Bool) {
        offset = min(0, max(-deleteWidth, offset + delta))
        if offset <= -deleteWidth * 0.6, hapticArmed { haptic(); hapticArmed = false }
        else if offset > -deleteWidth * 0.6 { hapticArmed = true }
        if ended {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                offset = offset <= -deleteWidth * 0.5 ? -deleteWidth : 0
            }
        }
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

/// Hosts SwiftUI content in an NSView that reports horizontal trackpad swipes
/// and lets vertical scrolls bubble to the enclosing list.
private struct SwipeCatcher<Content: View>: NSViewRepresentable {
    let onScroll: (CGFloat, Bool) -> Void
    let content: AnyView

    init(onScroll: @escaping (CGFloat, Bool) -> Void, @ViewBuilder content: () -> Content) {
        self.onScroll = onScroll
        self.content = AnyView(content())
    }

    func makeNSView(context: Context) -> ScrollNSView {
        let v = ScrollNSView()
        v.onScroll = onScroll
        let host = NSHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(host)
        v.host = host
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: v.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: v.trailingAnchor),
            host.topAnchor.constraint(equalTo: v.topAnchor),
            host.bottomAnchor.constraint(equalTo: v.bottomAnchor),
        ])
        return v
    }

    func updateNSView(_ v: ScrollNSView, context: Context) {
        v.onScroll = onScroll
        v.host?.rootView = content
    }

    final class ScrollNSView: NSView {
        var onScroll: ((CGFloat, Bool) -> Void)?
        var host: NSHostingView<AnyView>?

        override func scrollWheel(with e: NSEvent) {
            // Horizontal-dominant → swipe; otherwise let the list scroll.
            if abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) + 0.1 {
                let ended = e.phase == .ended || e.phase == .cancelled || e.momentumPhase == .ended
                onScroll?(e.scrollingDeltaX, ended)
            } else {
                super.scrollWheel(with: e)
            }
        }
    }
}
