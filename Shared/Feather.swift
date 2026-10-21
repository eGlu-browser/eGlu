import SwiftUI

/// A scrolled list's ends fade out where more of it lies beyond them, rather
/// than being cut by the edge: the tabs in a sidebar, at its top and foot;
/// the tabs along the top, at either side. An end with nothing beyond it is
/// left whole, so a list that fits has no fade at all. The iPad's and the
/// Mac's (the Mac app has this file too).
extension View {
    func feathered(_ axis: Axis, length: CGFloat = 20) -> some View {
        modifier(Feather(axis: axis, length: length))
    }
}

private struct Feather: ViewModifier {
    let axis: Axis
    let length: CGFloat
    /// More of the list before its start, and after its end.
    @State private var before = false
    @State private var after = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            content
                .onScrollGeometryChange(for: Ends.self) { geometry in
                    let horizontal = axis == .horizontal
                    let offset = horizontal ? geometry.contentOffset.x + geometry.contentInsets.leading
                                            : geometry.contentOffset.y + geometry.contentInsets.top
                    let shown = horizontal ? geometry.containerSize.width : geometry.containerSize.height
                    let whole = horizontal ? geometry.contentSize.width : geometry.contentSize.height
                    return Ends(before: offset > 1, after: offset + shown < whole - 1)
                } action: { _, ends in
                    withAnimation(.easeOut(duration: 0.18)) {
                        before = ends.before
                        after = ends.after
                    }
                }
                .mask { mask }
        } else {
            content
        }
    }

    private struct Ends: Equatable {
        let before: Bool
        let after: Bool
    }

    private var mask: some View {
        let lead = before ? length : 0
        let trail = after ? length : 0
        return Group {
            if axis == .horizontal {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: lead)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: trail)
                }
            } else {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: lead)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: trail)
                }
            }
        }
    }
}
