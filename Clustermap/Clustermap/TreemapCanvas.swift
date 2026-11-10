import ClustermapCore
import SwiftUI

/// The whole map in one `Canvas`. Layout is a pure function of the tree and the view size,
/// so hit testing uses the same rectangles that were drawn.
struct TreemapCanvas: View {
    @Environment(AppModel.self) private var model
    @State private var pointer: CGPoint?

    private let margin: CGFloat = 8

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: margin, dy: margin)
            let tiles = Treemap.layout(model.zoomNode, in: bounds)
            let hovered = pointer.flatMap { Treemap.hitTest(tiles, at: $0) }
            let palette = model.palette
            let selected = model.selectedPodID

            Canvas { context, _ in
                for tile in tiles {
                    draw(tile, in: &context, palette: palette, hovered: tile.id == hovered?.id, selected: selected)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): pointer = location
                case .ended: pointer = nil
                }
            }
            .gesture(
                SpatialTapGesture().onEnded { value in
                    tap(Treemap.hitTest(tiles, at: value.location))
                }
            )
            .overlay(alignment: .topLeading) {
                if let hovered, let pointer {
                    Tooltip(tile: hovered, pod: model.snapshot?.pod(hovered.node.podID))
                        .fixedSize()
                        .modifier(FollowPointer(pointer: pointer, container: geometry.size))
                        .allowsHitTesting(false)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Treemap of \(model.zoomNode.name)")
            .accessibilityValue(
                "\(model.zoomNode.podCount) pods, \(model.zoomNode.warningCount) warning, \(model.zoomNode.criticalCount) critical")
        }
    }

    private func tap(_ tile: TreemapTile?) {
        guard let tile else {
            model.selectedPodID = nil
            return
        }
        if let pod = tile.node.podID {
            model.select(pod: pod)
        } else {
            model.selectedPodID = nil
            model.zoom(into: tile.id)
        }
    }

    // MARK: Drawing

    private func draw(_ tile: TreemapTile, in context: inout GraphicsContext, palette: Palette, hovered: Bool, selected: String?) {
        let rect = tile.rect
        guard rect.width >= 1, rect.height >= 1 else { return }
        let node = tile.node

        switch tile.style {
        case .group:
            let shape = Path(roundedRect: rect, cornerRadius: 5)
            context.fill(shape, with: .color(.primary.opacity(hovered ? 0.11 : 0.05)))
            context.stroke(shape, with: .color(.primary.opacity(hovered ? 0.4 : 0.14)), lineWidth: 1)
            guard let header = tile.header else { return }
            // The dot carries the group's worst pod, so trouble shows before zooming in.
            let dot = CGRect(x: header.minX + 7, y: header.midY - 3.5, width: 7, height: 7)
            context.fill(Path(ellipseIn: dot), with: .color(palette.fill(node.score)))
            let weight: Font.Weight = tile.depth == 0 ? .semibold : .medium
            let titleWidth = label(
                node.name, at: CGPoint(x: dot.maxX + 5, y: header.midY), width: header.width - 24,
                font: .system(size: 11, weight: weight), color: .primary, in: &context)
            let remaining = header.width - 24 - titleWidth - 8
            if remaining > 44 {
                label(
                    node.detail, at: CGPoint(x: dot.maxX + 5 + titleWidth + 6, y: header.midY), width: remaining,
                    font: .system(size: 10), color: .secondary, in: &context)
            }

        case .leaf, .collapsed:
            let radius: CGFloat = min(4, min(rect.width, rect.height) / 4)
            let shape = Path(roundedRect: rect, cornerRadius: radius)
            context.fill(shape, with: .color(palette.fill(node.score)))
            if tile.style == .collapsed {
                // A group too small to open reads as a stack, not a pod.
                context.stroke(shape, with: .color(.primary.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            }
            if hovered {
                context.fill(shape, with: .color(.white.opacity(0.18)))
                context.stroke(shape, with: .color(.primary.opacity(0.6)), lineWidth: 1)
            }
            if let selected, node.podID == selected {
                context.stroke(Path(roundedRect: rect.insetBy(dx: 1, dy: 1), cornerRadius: radius), with: .color(.primary), lineWidth: 2)
            }

            guard rect.width >= 44, rect.height >= 18 else { return }
            let color = palette.text(on: node.score)
            let twoLines = rect.height >= 36 && !node.detail.isEmpty
            label(
                node.name, at: CGPoint(x: rect.minX + 5, y: twoLines ? rect.minY + 12 : rect.midY), width: rect.width - 10,
                font: .system(size: 11, weight: .medium), color: color, in: &context)
            if twoLines {
                label(
                    node.detail, at: CGPoint(x: rect.minX + 5, y: rect.minY + 26), width: rect.width - 10,
                    font: .system(size: 10), color: color.opacity(0.8), in: &context)
            }
        }
    }

    /// Draws one line of text, cut with an ellipsis when it does not fit. Returns the width used.
    @discardableResult
    private func label(
        _ string: String, at point: CGPoint, width: CGFloat, font: Font, color: Color, in context: inout GraphicsContext
    ) -> CGFloat {
        guard width > 12, !string.isEmpty else { return 0 }
        var resolved = context.resolve(Text(string).font(font).foregroundStyle(color))
        var size = resolved.measure(in: CGSize(width: CGFloat.infinity, height: 100))
        if size.width > width {
            let keep = Int(Double(string.count) * Double(width / size.width)) - 1
            guard keep >= 3 else { return 0 }
            resolved = context.resolve(Text(string.prefix(keep) + "…").font(font).foregroundStyle(color))
            size = resolved.measure(in: CGSize(width: CGFloat.infinity, height: 100))
        }
        context.draw(resolved, at: point, anchor: .leading)
        return min(size.width, width)
    }
}

private struct Tooltip: View {
    let tile: TreemapTile
    let pod: PodInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.node.name).font(.callout.weight(.semibold))
            if let pod {
                Text("\(pod.namespace) · \(pod.workload.title)")
                    .font(.caption).foregroundStyle(.secondary)
                Text(tile.node.detail).font(.caption)
            } else {
                Text("\(tile.node.kind.title) · \(tile.node.detail)").font(.caption).foregroundStyle(.secondary)
                if tile.node.criticalCount + tile.node.warningCount > 0 {
                    Text("\(tile.node.criticalCount) critical, \(tile.node.warningCount) warning").font(.caption)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

/// Keeps the tooltip next to the pointer and inside the map.
private struct FollowPointer: ViewModifier {
    let pointer: CGPoint
    let container: CGSize
    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let x = pointer.x + 14 + size.width > container.width ? pointer.x - size.width - 10 : pointer.x + 14
        let y = pointer.y + 18 + size.height > container.height ? pointer.y - size.height - 8 : pointer.y + 18
        content
            .onGeometryChange(for: CGSize.self, of: { $0.size }, action: { size = $0 })
            .offset(x: max(4, x), y: max(4, y))
    }
}
