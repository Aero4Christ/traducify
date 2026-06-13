import SwiftUI

extension Color {
    /// Parse "#RRGGBB" or "#RRGGBBAA". Falls back to the given default on bad input.
    init(hex: String, default fallback: Color = .white) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let value = UInt64(s, radix: 16) else {
            self = fallback
            return
        }
        let r, g, b, a: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        } else {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// "#RRGGBB" for storing a ColorPicker value back into config.
    var hexString: String {
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? .white
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

/// Resolved colors + scale for the panel, derived from Config.
struct Theme {
    let bg: Color
    let text: Color
    let accent: Color
    let scale: CGFloat
    let opacity: Double

    init(_ c: Config) {
        bg = Color(hex: c.panelBgHex, default: .black)
        text = Color(hex: c.panelTextHex, default: .white)
        accent = Color(hex: c.accentHex, default: .green)
        scale = CGFloat(c.fontScale)
        opacity = c.panelOpacity
    }

    func textColor(_ o: Double) -> Color { text.opacity(o) }
    func size(_ base: CGFloat) -> CGFloat { (base * scale).rounded() }
}
