import SwiftUI

/// AppKit rounds window dimensions. Keep spare space below and to the left instead
/// of recentering the card by a different fraction of a point on every resize.
struct PanelContent<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }
}
