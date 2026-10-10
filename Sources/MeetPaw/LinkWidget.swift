import SwiftUI

/// Compact standalone popover shown on left-click: just the freshly created
/// meeting link with a copy button, with a bezier entrance animation.
struct LinkWidget: View {
    @Bindable var model: AppModel
    let onClose: () -> Void

    // A springy cubic-bezier for the pop-in.
    private var pop: Animation { .timingCurve(0.34, 1.4, 0.4, 1.0, duration: 0.42) }

    var body: some View {
        ZStack {
            if let link = model.createdLink {
                GlassLinkCard(url: link,
                              copy: {
                                  model.copyLink()
                                  // Let the "Copied!" tick show, then dismiss.
                                  DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                      model.dismissCreatedLink(); onClose()
                                  }
                              },
                              join: { model.openCreatedLink(); model.dismissCreatedLink(); onClose() },
                              dismiss: { model.dismissCreatedLink(); onClose() })
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Creating meeting…").foregroundStyle(.secondary)
                }
                .padding(18)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 16)
                .transition(.opacity)
            }
        }
        .padding(12)
        .frame(width: 300)
        .tint(.meetpaw)
        .animation(pop, value: model.createdLink)
    }
}
