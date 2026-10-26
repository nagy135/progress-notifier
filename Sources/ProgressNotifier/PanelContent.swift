import SwiftUI

/// AppKit rounds window dimensions. Keep spare space away from the anchored corner
/// instead of recentering the card by a different fraction of a point on every resize.
struct PanelContent<Content: View>: View {
    var placement: PanelPlacement
    let content: Content

    init(placement: PanelPlacement = .topRight, @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: placement.contentAlignment)
    }
}
