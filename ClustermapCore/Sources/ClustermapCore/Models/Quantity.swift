import Foundation

/// Kubernetes resource quantities: `250m`, `1500n`, `128Mi`, `1G`, `2`, `1e3`.
/// CPU parses to cores, memory to bytes.
public enum Quantity {
    private static let suffixes: [(String, Double)] = [
        ("Ki", 1024), ("Mi", 1_048_576), ("Gi", 1_073_741_824),
        ("Ti", 1_099_511_627_776), ("Pi", 1_125_899_906_842_624), ("Ei", 1_152_921_504_606_846_976),
        ("n", 1e-9), ("u", 1e-6), ("m", 1e-3),
        ("k", 1e3), ("M", 1e6), ("G", 1e9), ("T", 1e12), ("P", 1e15), ("E", 1e18),
    ]

    public static func parse(_ string: String?) -> Double? {
        guard let string = string?.trimmingCharacters(in: .whitespaces), !string.isEmpty else { return nil }
        // Plain and exponent forms first, so `1E3` is not read as 1 exa followed by junk.
        if let value = Double(string) { return value }
        for (suffix, multiplier) in suffixes where string.hasSuffix(suffix) {
            if let number = Double(string.dropLast(suffix.count)) { return number * multiplier }
        }
        return nil
    }
}

public enum Format {
    public static func cpu(_ cores: Double) -> String {
        if cores < 0.0005 { return "0m" }
        if cores < 1 { return "\(Int((cores * 1000).rounded()))m" }
        return trimmed(cores, digits: 2) + (cores == 1 ? " core" : " cores")
    }

    public static func bytes(_ bytes: Double) -> String {
        let units = ["B", "Ki", "Mi", "Gi", "Ti", "Pi"]
        var value = bytes
        var unit = 0
        while value >= 1024, unit < units.count - 1 {
            value /= 1024
            unit += 1
        }
        return trimmed(value, digits: value >= 100 || unit == 0 ? 0 : 1) + " " + units[unit]
    }

    public static func percent(_ ratio: Double) -> String {
        "\(Int((ratio * 100).rounded()))%"
    }

    public static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(value) \(value == 1 ? singular : (plural ?? singular + "s"))"
    }

    /// Short age such as `45s`, `12m`, `3h`, `5d`.
    public static func age(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86_400)d"
    }

    private static func trimmed(_ value: Double, digits: Int) -> String {
        var text = String(format: "%.\(digits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text
    }
}
