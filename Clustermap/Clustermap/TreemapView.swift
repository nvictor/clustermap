//
//  TreemapView.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import SwiftUI

struct TreemapView: View {
    @EnvironmentObject private var viewModel: ClusterViewModel

    let node: TreeNode
    let maxLeafValue: Double
    let path: [UUID]
    @State private var hoveredPath: [UUID]?

    init(node: TreeNode, maxLeafValue: Double? = nil, path: [UUID]? = nil) {
        self.node = node
        self.maxLeafValue = maxLeafValue ?? 1.0
        self.path = path ?? [node.id]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: node.isLeaf ? .center : .topLeading) {
                backgroundView
                if node.isLeaf {
                    leafView
                } else {
                    labelView(geometry: geometry)
                    childrenView(geometry: geometry)
                }
            }
        }
        .background(Color(.windowBackgroundColor))
        .clipped()
        .padding(LayoutConstants.mainPadding)
    }

    private var backgroundView: some View {
        Rectangle()
            .fill(nodeColor)
            .border(.black, width: LayoutConstants.borderWidth)
            .overlay(isHovered ? Color.black.opacity(ColorConstants.hoverOpacity) : .clear)
            .onHover(perform: handleHover)
            .contentShape(Rectangle())
            .onTapGesture(perform: handleTap)
    }

    private var leafView: some View {
        VStack {
            Text(node.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(formatValue(node.value))
                .font(.caption2)
                .opacity(0.8)
        }
        .foregroundColor(readableTextColor)
        .padding(4)
        .contentShape(Rectangle())
        .help("\(node.name)\nValue: \(node.value)")
    }

    private func labelView(geometry: GeometryProxy) -> some View {
        Text(labelText)
            .font(.caption)
            .fontWeight(.medium)
            .multilineTextAlignment(.center)
            .foregroundStyle(labelColor)
            .frame(width: geometry.size.width - LayoutConstants.textPadding)
            .padding(.top, LayoutConstants.textVerticalPadding)
            .padding(.bottom, LayoutConstants.textVerticalPadding)
    }

    private func childrenView(geometry: GeometryProxy) -> some View {
        ForEach(layoutChildren(in: geometry.size)) { child in
            TreemapView(
                node: child.node, maxLeafValue: maxLeafValue, path: path + [child.node.id]
            )
            .frame(width: child.frame.width, height: child.frame.height)
            .position(x: child.frame.midX, y: child.frame.midY)
        }
    }

    private var labelText: String {
        // path.count == 1 is the root "Cluster" node.
        // path.count == 2 is a namespace node.
        if path.count == 2 && !node.isLeaf {
            return "\(node.name) (\(node.children.count))"
        }
        return node.name
    }

    private var nodeColor: Color {
        if node.isLeaf {
            guard maxLeafValue > 0 else { return .gray }
            let ratio = node.value / maxLeafValue
            return Color(hue: 0.08 + 0.22 * (1 - ratio), saturation: 0.8, brightness: 0.9)
        } else {
            return Color.from(string: node.name)
        }
    }

    private var readableTextColor: Color {
        nodeColor.luminance > 0.5 ? .black : .white
    }

    private var labelColor: Color {
        let zoomController = ZoomController(selectedPath: viewModel.selectedPath, currentPath: path)
        if zoomController.shouldHighlightLabel() {
            return readableTextColor
        } else {
            return .gray
        }
    }

    private var isHovered: Bool {
        hoveredPath?.starts(with: path) ?? false
    }

    private func handleHover(_ hovering: Bool) {
        hoveredPath = hovering ? path : (hoveredPath == path ? nil : hoveredPath)
    }

    private func handleTap() {
        if path.count == 1 {
            // Root node - clear selection
            viewModel.selectedPath = nil
        } else if !node.isLeaf {
            // Non-leaf node - toggle zoom
            viewModel.selectedPath = (viewModel.selectedPath == path) ? nil : path
        }
    }

    private func layoutChildren(in size: CGSize) -> [ChildLayout] {
        let zoomController = ZoomController(selectedPath: viewModel.selectedPath, currentPath: path)

        guard zoomController.shouldShowChildren else { return [] }

        let availableRect = calculateAvailableRect(in: size)
        guard isRectLargeEnough(availableRect) else { return [] }

        let visibleChildren = zoomController.getVisibleChildren(from: node.children)
        guard !visibleChildren.isEmpty else { return [] }

        return TreemapLayoutCalculator.layout(children: visibleChildren, in: availableRect)
    }

    private func calculateAvailableRect(in size: CGSize) -> CGRect {
        CGRect(
            x: LayoutConstants.padding,
            y: LayoutConstants.captionHeight + LayoutConstants.padding,
            width: size.width - 2 * LayoutConstants.padding,
            height: size.height - LayoutConstants.captionHeight - 2 * LayoutConstants.padding
        )
    }

    private func isRectLargeEnough(_ rect: CGRect) -> Bool {
        rect.width > LayoutConstants.minDisplayWidth
            && rect.height > LayoutConstants.minDisplayHeight
    }

    private func formatValue(_ v: Double) -> String {
        if viewModel.metric == .cpu && v < 1.0 && v > 0 {
            return String(format: "%.0fm", v * 1000)
        }
        if v >= 1_000_000_000 { return String(format: "%.1fG", v / 1_000_000_000) }
        if v >= 1_000_000 { return String(format: "%.1fM", v / 1_000_000) }
        if v >= 1000 { return String(format: "%.0fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}

struct ChildLayout: Identifiable {
    let id = UUID()
    let node: TreeNode
    let frame: CGRect
}

func isPrefix(of path: [UUID], prefix: [UUID]) -> Bool {
    guard prefix.count <= path.count else { return false }
    return !zip(prefix, path).contains { $0 != $1 }
}

struct ZoomController {
    let selectedPath: [UUID]?
    let currentPath: [UUID]

    var shouldShowChildren: Bool {
        guard let selectedPath = selectedPath else { return true }

        // If this node is selected, show all children
        if currentPath == selectedPath { return true }

        // If this path leads to the selected path, show children
        if isPrefix(of: selectedPath, prefix: currentPath) { return true }

        // Otherwise, don't show children
        return false
    }

    func getVisibleChildren(from children: [TreeNode]) -> [TreeNode] {
        guard let selectedPath = selectedPath else { return children }

        // If this node is selected, show all children
        if currentPath == selectedPath { return children }

        // If this path leads to the selected path, show only the relevant child
        if isPrefix(of: selectedPath, prefix: currentPath) {
            let nextIndex = currentPath.count
            if selectedPath.count > nextIndex,
                let relevantChild = children.first(where: { $0.id == selectedPath[nextIndex] })
            {
                return [relevantChild]
            }
        }

        return []
    }

    func shouldHighlightLabel() -> Bool {
        guard let selectedPath = selectedPath else { return true }

        return selectedPath == currentPath || isPrefix(of: selectedPath, prefix: currentPath)
            || isPrefix(of: currentPath, prefix: selectedPath)
    }
}

struct TreemapLayoutCalculator {
    static func layout(children: [TreeNode], in rect: CGRect) -> [ChildLayout] {
        let sortedChildren = children.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard !sortedChildren.isEmpty else { return [] }

        let total = sortedChildren.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }

        var result: [ChildLayout] = []
        let scale = sqrt(total / Double(rect.width * rect.height))
        var currentRect = rect
        var index = 0

        while index < sortedChildren.count {
            let (spanRect, endIndex, sum) = calculateSpan(
                children: sortedChildren,
                currentRect: currentRect,
                scale: scale,
                total: total,
                startIndex: index
            )

            if sum / total < LayoutConstants.minValueThreshold { break }

            let layouts = createLayoutsForSpan(
                children: sortedChildren,
                spanRect: spanRect,
                startIndex: index,
                endIndex: endIndex,
                sum: sum,
                scale: scale
            )

            result.append(contentsOf: layouts)
            currentRect = updateRectAfterSpan(currentRect: currentRect, spanRect: spanRect)
            index = endIndex
        }

        return result
    }

    private static func calculateSpan(
        children: [TreeNode],
        currentRect: CGRect,
        scale: Double,
        total: Double,
        startIndex: Int
    ) -> (spanRect: CGRect, endIndex: Int, sum: Double) {
        let horizontal = currentRect.width >= currentRect.height
        let space = scale * Double(horizontal ? currentRect.width : currentRect.height)
        let (endIndex, sum) = selectOptimalSpan(children: children, space: space, start: startIndex)

        let spanRect: CGRect
        if horizontal {
            let height = (sum / space) / scale
            spanRect = CGRect(
                x: currentRect.minX, y: currentRect.minY,
                width: currentRect.width, height: height
            )
        } else {
            let width = (sum / space) / scale
            spanRect = CGRect(
                x: currentRect.minX, y: currentRect.minY,
                width: width, height: currentRect.height
            )
        }

        return (spanRect, endIndex, sum)
    }

    private static func createLayoutsForSpan(
        children: [TreeNode],
        spanRect: CGRect,
        startIndex: Int,
        endIndex: Int,
        sum: Double,
        scale: Double
    ) -> [ChildLayout] {
        var result: [ChildLayout] = []
        var cellRect = spanRect
        let horizontal = spanRect.width >= spanRect.height
        let space = scale * Double(horizontal ? spanRect.width : spanRect.height)

        for i in startIndex..<endIndex {
            let child = children[i]
            let frame = calculateChildFrame(
                child: child,
                cellRect: &cellRect,
                horizontal: horizontal,
                sum: sum,
                space: space,
                scale: scale
            )

            if frame.width > LayoutConstants.minNodeWidth
                && frame.height >= LayoutConstants.minNodeHeight
            {
                result.append(ChildLayout(node: child, frame: frame))
            }
        }

        return result
    }

    private static func calculateChildFrame(
        child: TreeNode,
        cellRect: inout CGRect,
        horizontal: Bool,
        sum: Double,
        space: Double,
        scale: Double
    ) -> CGRect {
        if horizontal {
            let width = (child.value / (sum / space)) / scale
            defer { cellRect.origin.x += width }
            return CGRect(
                x: cellRect.minX, y: cellRect.minY,
                width: width, height: cellRect.height
            )
        } else {
            let height = (child.value / (sum / space)) / scale
            defer { cellRect.origin.y += height }
            return CGRect(
                x: cellRect.minX, y: cellRect.minY,
                width: cellRect.width, height: height
            )
        }
    }

    private static func updateRectAfterSpan(currentRect: CGRect, spanRect: CGRect) -> CGRect {
        var newRect = currentRect
        if spanRect.width >= spanRect.height {
            // Horizontal span
            newRect.origin.y += spanRect.height
            newRect.size.height -= spanRect.height
        } else {
            // Vertical span
            newRect.origin.x += spanRect.width
            newRect.size.width -= spanRect.width
        }
        return newRect
    }

    private static func selectOptimalSpan(children: [TreeNode], space: Double, start: Int) -> (
        end: Int, sum: Double
    ) {
        var minValue = children[start].value
        var maxValue = minValue
        var sum = 0.0
        var lastScore = Double.infinity
        var end = start

        for i in start..<children.count {
            let value = children[i].value
            minValue = min(minValue, value)
            maxValue = max(maxValue, value)
            let newSum = sum + value
            let score = max(
                (maxValue * space * space) / (newSum * newSum),
                (newSum * newSum) / (minValue * space * space)
            )
            if score > lastScore { break }
            lastScore = score
            sum = newSum
            end = i + 1
        }
        return (end, sum)
    }
}
