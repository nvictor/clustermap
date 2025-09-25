//
//  Constants.swift
//  Clustermap
//
//  Created by Victor Noagbodji on 8/16/25.
//

import Foundation
import SwiftUI

struct LayoutConstants {
    static let captionHeight: CGFloat = 12
    static let padding: CGFloat = 3
    static let minNodeWidth: CGFloat = 20
    static let minNodeHeight: CGFloat = 14
    static let minDisplayWidth: CGFloat = 40
    static let minDisplayHeight: CGFloat = 28
    static let borderWidth: CGFloat = 0.5
    static let textPadding: CGFloat = 6
    static let textVerticalPadding: CGFloat = 4
    static let mainPadding: CGFloat = 8
    static let minValueThreshold: Double = 0.1
}

struct ColorConstants {
    static let saturation: Double = 0.7
    static let brightness: Double = 0.8
    static let hoverOpacity: Double = 0.2
}

enum SizingMetric: String, CaseIterable, Identifiable {
    case count = "Count"
    case cpu = "CPU"
    case memory = "Memory"
    var id: String { rawValue }
}

extension Color {
    static func from(string: String) -> Color {
        var hash: Int = 0
        for char in string.unicodeScalars {
            hash = 31 &* hash &+ Int(char.value)
        }
        // Using the golden ratio to pick well-distributed colors.
        let hue = fmod(abs(Double(hash)) * 0.618033988749895, 1.0)
        return Color(
            hue: hue,
            saturation: ColorConstants.saturation,
            brightness: ColorConstants.brightness
        )
    }

    var luminance: Double {
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        NSColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}
