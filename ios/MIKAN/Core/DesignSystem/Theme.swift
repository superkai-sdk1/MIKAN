import SwiftUI
import UIKit

enum Theme {
    static let cardRadius: CGFloat = 22
    static let auraHeight: CGFloat = 380

    /// Preset master colors for the calendar.
    static let masterPalette = [
        "#FF7A1A", "#E5484D", "#D6409F", "#8E4EC6", "#6E56CF",
        "#0090FF", "#12A594", "#30A46C", "#F5A524", "#8D8D8D",
    ]

    static let mandarinLight = Color(red: 1.0, green: 0.69, blue: 0.29)
    static let mandarin = Color(red: 1.0, green: 0.48, blue: 0.10)
    static let mandarinDeep = Color(red: 0.93, green: 0.35, blue: 0.02)
}

extension Color {
    /// Parses "#RRGGBB" (or "RRGGBB").
    init?(hex: String?) {
        guard let raw = hex.nonEmpty else { return nil }
        let value = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }

    /// Master color with the brand accent as fallback.
    static func master(_ hex: String?) -> Color {
        Color(hex: hex) ?? .accentColor
    }

    /// "#RRGGBB" in sRGB.
    var hexString: String {
        let resolved = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func component(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }
}

/// Warm mandarin glow behind headers, so the glass navigation layer has something to refract.
struct AuraBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemGroupedBackground)
            LinearGradient(
                colors: [Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.22), Color.accentColor.opacity(0.06), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: Theme.auraHeight)
            RadialGradient(
                colors: [Theme.mandarinLight.opacity(colorScheme == .dark ? 0.22 : 0.30), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: Theme.auraHeight
            )
            .frame(height: Theme.auraHeight)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Hides the default scroll background and shows the warm aura behind the content.
    func auraBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { AuraBackground() }
    }

    /// Standard content card — not glass; glass is reserved for the control layer.
    func cardStyle(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

/// Studio wordmark from docs/brand/mikan-logo.pdf (Logo.imageset, vector template):
/// black in light mode, white in dark mode. Regenerate with ios/Scripts/generate_icon.swift.
struct BrandLogo: View {
    var height: CGFloat = 40

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .foregroundStyle(.primary)
            .accessibilityLabel("MIKAN")
    }
}
