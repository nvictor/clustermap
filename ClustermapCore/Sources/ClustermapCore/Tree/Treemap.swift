import CoreGraphics
import Foundation

public struct TreemapTile: Identifiable, Sendable {
    public enum Style: Sendable, Equatable {
        /// A pod.
        case leaf
        /// A group with room for a header and its children.
        case group
        /// A group too small to open. Drawn as one tile in its worst child's color.
        case collapsed
    }

    public let node: TreeNode
    public let rect: CGRect
    public let depth: Int
    public let style: Style
    /// The title strip of an open group.
    public let header: CGRect?

    public var id: String { node.id }
}

public struct TreemapOptions: Sendable {
    public var headerHeight: CGFloat = 20
    /// Space between sibling tiles.
    public var gap: CGFloat = 2
    /// Space between a group's border and its children.
    public var padding: CGFloat = 3
    /// Groups smaller than this collapse into a single tile.
    public var minGroupSize = CGSize(width: 56, height: 44)

    public init() {}
}

public enum Treemap {
    /// Squarified treemap (Bruls, Huizing, van Wijk). `values` must be sorted largest first.
    /// Returns one rectangle per value, in the same order, tiling `rect` exactly.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var rects = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return rects }

        let scale = Double(rect.width * rect.height) / total
        var free = rect
        var start = 0
        while start < values.count {
            let side = Double(min(free.width, free.height))
            guard side > 0 else { break }

            // Grow the row while the worst aspect ratio keeps improving.
            var end = start
            var sum = 0.0
            var smallest = Double.infinity
            var largest = 0.0
            var best = Double.infinity
            while end < values.count {
                let area = values[end] * scale
                guard area > 0 else { end += 1; continue }
                let newSum = sum + area
                let low = min(smallest, area)
                let high = max(largest, area)
                let worst = max(side * side * high / (newSum * newSum), newSum * newSum / (side * side * low))
                if worst > best { break }
                best = worst
                sum = newSum
                smallest = low
                largest = high
                end += 1
            }
            guard sum > 0 else { break }

            // The row runs along the short side and takes `thickness` off the long side.
            let thickness = sum / side
            let wide = free.width >= free.height
            var offset = 0.0
            for index in start..<end {
                let length = values[index] * scale / thickness
                rects[index] =
                    wide
                    ? CGRect(x: free.minX, y: free.minY + offset, width: thickness, height: length)
                    : CGRect(x: free.minX + offset, y: free.minY, width: length, height: thickness)
                offset += length
            }
            free =
                wide
                ? CGRect(x: free.minX + thickness, y: free.minY, width: max(0, free.width - thickness), height: free.height)
                : CGRect(x: free.minX, y: free.minY + thickness, width: free.width, height: max(0, free.height - thickness))
            start = end
        }
        return rects
    }

    /// Lays out the children of `root` inside `rect`. Tiles come back parents first, so drawing in order
    /// paints children on top and the last tile containing a point is the deepest one.
    public static func layout(_ root: TreeNode, in rect: CGRect, options: TreemapOptions = TreemapOptions()) -> [TreemapTile] {
        var tiles: [TreemapTile] = []
        guard rect.width > 0, rect.height > 0 else { return tiles }
        if root.isLeaf {
            tiles.append(TreemapTile(node: root, rect: rect, depth: 0, style: .leaf, header: nil))
        } else {
            place(root.children, in: rect, depth: 0, options: options, into: &tiles)
        }
        return tiles
    }

    public static func hitTest(_ tiles: [TreemapTile], at point: CGPoint) -> TreemapTile? {
        tiles.last { $0.rect.contains(point) }
    }

    private static func place(
        _ nodes: [TreeNode], in rect: CGRect, depth: Int, options: TreemapOptions, into tiles: inout [TreemapTile]
    ) {
        let visible = nodes.filter { $0.size > 0 }
        let rects = squarify(visible.map(\.size), in: rect)
        let inset = options.gap / 2
        for (node, cell) in zip(visible, rects) {
            let frame = cell.width > options.gap * 2 && cell.height > options.gap * 2 ? cell.insetBy(dx: inset, dy: inset) : cell
            guard frame.width > 0, frame.height > 0 else { continue }
            if node.isLeaf {
                tiles.append(TreemapTile(node: node, rect: frame, depth: depth, style: .leaf, header: nil))
                continue
            }
            let inner = CGRect(
                x: frame.minX + options.padding,
                y: frame.minY + options.headerHeight,
                width: frame.width - options.padding * 2,
                height: frame.height - options.headerHeight - options.padding)
            guard frame.width >= options.minGroupSize.width, frame.height >= options.minGroupSize.height,
                inner.width > 0, inner.height > 0
            else {
                tiles.append(TreemapTile(node: node, rect: frame, depth: depth, style: .collapsed, header: nil))
                continue
            }
            let header = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: options.headerHeight)
            tiles.append(TreemapTile(node: node, rect: frame, depth: depth, style: .group, header: header))
            place(node.children, in: inner, depth: depth + 1, options: options, into: &tiles)
        }
    }
}
