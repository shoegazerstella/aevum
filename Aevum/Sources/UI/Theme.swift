// Theme.swift — Aevum design system.
// Centralized tokens (color, typography, spacing, radii, motion) plus
// reusable view modifiers and controls. Every view imports from here so
// the visual language stays coherent.

import SwiftUI

// MARK: - Color tokens

enum AevumColors {
    static let bg          = Color(hex: 0x0A0B0E)!
    static let bgDeep      = Color(hex: 0x060709)!
    static let panel       = Color(hex: 0x13151A)!
    static let panelRaised = Color(hex: 0x1C1F26)!
    static let panelHover  = Color(hex: 0x23262F)!
    static let divider     = Color.white.opacity(0.06)
    static let dividerStrong = Color.white.opacity(0.10)

    static let text       = Color(hex: 0xE8E9ED)!
    static let textDim    = Color(hex: 0x8B8E96)!
    static let textFaint  = Color(hex: 0x5A5D65)!

    static let amber      = Color(hex: 0xFFB547)!
    static let cyan       = Color(hex: 0x3DD9EB)!
    static let danger     = Color(hex: 0xFF5E6C)!
    static let good       = Color(hex: 0x4ADE80)!

    // The blend axis — amber to cyan. Used for morph-state gradients.
    static func blendAxis(at t: Double) -> Color {
        Color.interpolate(from: amber, to: cyan, t: t)
    }
}

extension Color {
    init?(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }

    static func interpolate(from a: Color, to b: Color, t: Double) -> Color {
        let t = max(0, min(1, t))
        guard let c1 = a.cgColor?.components, let c2 = b.cgColor?.components,
              c1.count >= 3, c2.count >= 3 else {
            return t < 0.5 ? a : b
        }
        let gt = CGFloat(t)
        return Color(red: Double(c1[0] + (c2[0] - c1[0]) * gt),
                     green: Double(c1[1] + (c2[1] - c1[1]) * gt),
                     blue: Double(c1[2] + (c2[2] - c1[2]) * gt))
    }
}

// MARK: - Typography

enum AevumFont {
    static let title      = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let headline   = Font.system(size: 13, weight: .semibold)
    static let body       = Font.system(size: 12, weight: .regular)
    static let caption    = Font.system(size: 11, weight: .regular)
    static let micro      = Font.system(size: 10, weight: .regular)
    static let mono       = Font.system(size: 11, weight: .regular, design: .monospaced)
    static let monoBold   = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let bigNumber  = Font.system(size: 28, weight: .medium, design: .rounded)
}

// MARK: - Spacing & radii

enum AevumSpacing {
    static let xs: CGFloat = 4
    static let s: CGFloat  = 8
    static let m: CGFloat  = 12
    static let l: CGFloat  = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum AevumRadius {
    static let small: CGFloat  = 6
    static let medium: CGFloat = 10
    static let large: CGFloat  = 14
}

// MARK: - Motion

enum AevumMotion {
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.78)
    static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.85)
    static let glow   = Animation.easeInOut(duration: 1.8).repeatForever(autoreverses: true)
}

// MARK: - Reusable modifiers

struct GlassBackground: ViewModifier {
    var radius: CGFloat = AevumRadius.medium
    var inset: CGFloat = 0
    var raised: Bool = false
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(raised ? AevumColors.panelRaised : AevumColors.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(AevumColors.divider, lineWidth: 1)
            )
    }
}

extension View {
    func glass(radius: CGFloat = AevumRadius.medium, raised: Bool = false) -> some View {
        modifier(GlassBackground(radius: radius, raised: raised))
    }
    func aevumShadow() -> some View {
        shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Custom controls

struct AevumSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    var accent: Color = AevumColors.amber

    var body: some View {
        HStack(spacing: AevumSpacing.s) {
            Text(label)
                .font(AevumFont.caption)
                .foregroundStyle(AevumColors.textDim)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                let norm = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AevumColors.panelRaised)
                        .frame(height: 3)
                    Capsule()
                        .fill(
                            LinearGradient(colors: [accent.opacity(0.7), accent],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(0, geo.size.width * CGFloat(norm)), height: 3)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 11, height: 11)
                        .shadow(color: accent.opacity(0.6), radius: 4)
                        .offset(x: max(0, geo.size.width * CGFloat(norm)) - 5.5)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let n = max(0, min(1, v.location.x / geo.size.width))
                            value = range.lowerBound + n * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 18)
            Text(String(format: format, value))
                .font(AevumFont.mono)
                .foregroundStyle(AevumColors.text)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

struct AevumToggle: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: AevumSpacing.s) {
                Text(label).font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
                Spacer()
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? AevumColors.amber.opacity(0.85) : AevumColors.panelRaised)
                        .frame(width: 30, height: 16)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 12, height: 12)
                        .padding(2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct AevumPillButton: View {
    let title: String
    let systemImage: String?
    @Binding var isSelected: Bool
    var action: () -> Void
    init(_ title: String, systemImage: String? = nil, isSelected: Binding<Bool>, action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage
        self._isSelected = isSelected; self.action = action
    }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let si = systemImage { Image(systemName: si).font(.system(size: 9)) }
                Text(title).font(AevumFont.caption)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? AevumColors.amber.opacity(0.18) : AevumColors.panelRaised)
            )
            .foregroundStyle(isSelected ? AevumColors.amber : AevumColors.textDim)
            .overlay(
                Capsule().strokeBorder(isSelected ? AevumColors.amber.opacity(0.5) : AevumColors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
