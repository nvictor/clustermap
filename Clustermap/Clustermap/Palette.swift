import AppKit
import SwiftUI

/// A color scheme for health scores: one color each for healthy (0), warning (0.5), and critical (1).
struct Palette: Identifiable, Equatable {
    struct RGB: Equatable {
        var red: Double
        var green: Double
        var blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        func mixed(with other: RGB, _ amount: Double) -> RGB {
            RGB(
                red + (other.red - red) * amount, green + (other.green - green) * amount,
                blue + (other.blue - blue) * amount)
        }

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

        /// Relative luminance (WCAG), used to pick black or white text.
        var luminance: Double {
            func linear(_ value: Double) -> Double {
                value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
    }

    let id: String
    let name: String
    let healthy: RGB
    let warning: RGB
    let critical: RGB

    static let classic = Palette(
        id: "classic", name: "Classic", healthy: RGB(hex: 0x34A853), warning: RGB(hex: 0xF2C12E), critical: RGB(hex: 0xD93A32))
    static let colorblind = Palette(
        id: "colorblind", name: "Colorblind Safe", healthy: RGB(hex: 0x2C7BB6), warning: RGB(hex: 0xE4E4E0), critical: RGB(hex: 0xE66101))
    static let viridis = Palette(
        id: "viridis", name: "Viridis", healthy: RGB(hex: 0x440154), warning: RGB(hex: 0x21908C), critical: RGB(hex: 0xFDE725))
    static let heat = Palette(
        id: "heat", name: "Heat", healthy: RGB(hex: 0xFFF1A8), warning: RGB(hex: 0xF28C28), critical: RGB(hex: 0x8B0000))

    /// Follows the system accent color: pale when healthy, full strength when critical.
    static var mono: Palette {
        let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
        let full = RGB(Double(accent.redComponent), Double(accent.greenComponent), Double(accent.blueComponent))
        let pale = RGB(0.82, 0.83, 0.85)
        return Palette(id: "mono", name: "Mono", healthy: pale, warning: pale.mixed(with: full, 0.55), critical: full)
    }

    static var all: [Palette] { [.classic, .colorblind, .viridis, .heat, .mono] }

    static func named(_ id: String) -> Palette {
        all.first { $0.id == id } ?? .classic
    }

    func rgb(_ score: Double) -> RGB {
        let value = min(1, max(0, score))
        return value < 0.5 ? healthy.mixed(with: warning, value * 2) : warning.mixed(with: critical, (value - 0.5) * 2)
    }

    /// Tiles with no data (no metrics, or no limit to compare against) are a neutral gray.
    static let noData = RGB(0.56, 0.57, 0.6)

    func fill(_ score: Double?) -> Color {
        score.map { rgb($0).color } ?? Palette.noData.color.opacity(0.45)
    }

    func text(on score: Double?) -> Color {
        guard let score else { return .primary }
        // Black wins the contrast ratio against anything lighter than this.
        return rgb(score).luminance > 0.179 ? Color.black.opacity(0.85) : .white
    }

    var gradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: healthy.color, location: 0), .init(color: warning.color, location: 0.5),
                .init(color: critical.color, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
    }
}
