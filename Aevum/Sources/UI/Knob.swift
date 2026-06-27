// Knob.swift — A rotary knob control for live parameter tweaking.
// Drag vertically to change the value; the arc fill + indicator show the
// current position. Double-click resets to default. Designed for the
// macro-knobs row above the prompt surface.

import SwiftUI

struct Knob: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double? = nil
    var format: String = "%.2f"
    var accent: Color = AevumColors.amber
    var size: CGFloat = 56

    @State private var dragStartValue: Double = 0

    private var norm: Double {
        let lo = range.lowerBound, hi = range.upperBound
        return hi > lo ? (value - lo) / (hi - lo) : 0
    }

    var body: some View {
        VStack(spacing: 4) {
            KnobDial(norm: norm, accent: accent, size: size)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { d in
                            // Vertical drag: up = increase. 120px = full range.
                            let delta = -d.translation.height / 120.0
                            let n = max(0, min(1, dragStartValue + delta))
                            value = range.lowerBound + n * (range.upperBound - range.lowerBound)
                        }
                        .onChanged { _ in } // keep alive
                )
                .onAppear { dragStartValue = norm }
                .onTapGesture(count: 2) {
                    if let dv = defaultValue { value = dv }
                }
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(AevumColors.textFaint)
                .lineLimit(1)
            Text(String(format: format, value))
                .font(AevumFont.mono)
                .foregroundStyle(accent)
        }
        // Ensure dragStartValue tracks external value changes so drag
        // always begins from the current position.
        .onChange(of: value) { _ in dragStartValue = norm }
    }
}

private struct KnobDial: View {
    let norm: Double // 0..1
    let accent: Color
    let size: CGFloat

    // Sweep from -225° (bottom-left) to +45° (bottom-right) = 270° arc.
    private let startAngle = Angle.degrees(-225)
    private let endAngle = Angle.degrees(45)
    private let totalSweep: Double = 270

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: totalSweep / 360)
                .stroke(AevumColors.panelRaised, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(startAngle)
                .frame(width: size, height: size)
            // Fill
            Circle()
                .trim(from: 0, to: max(0.001, norm * totalSweep / 360))
                .stroke(
                    LinearGradient(colors: [accent.opacity(0.6), accent],
                                   startPoint: .leading, endPoint: .trailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(startAngle)
                .frame(width: size, height: size)
                .shadow(color: accent.opacity(0.4), radius: 4)
            // Indicator dot at the current position
            let angle = startAngle + .degrees(norm * totalSweep)
            Circle()
                .fill(Color.white)
                .frame(width: 5, height: 5)
                .shadow(color: accent.opacity(0.8), radius: 3)
                .offset(x: cos(angle.radians) * size * 0.32,
                        y: sin(angle.radians) * size * 0.32)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

// MARK: - Float-backed Knob (bridges Double Knob ↔ Float engine params)

struct KnobFloat: View {
    let label: String
    let getValue: () -> Float
    let setValue: (Float) -> Void
    let range: ClosedRange<Float>
    var defaultValue: Float? = nil
    var format: String = "%.2f"
    var accent: Color = AevumColors.amber
    var size: CGFloat = 56

    @State private var displayValue: Double = 0

    var body: some View {
        Knob(
            label: label,
            value: Binding(
                get: { displayValue },
                set: { newValue in
                    displayValue = newValue
                    setValue(Float(newValue))
                }
            ),
            range: Double(range.lowerBound)...Double(range.upperBound),
            defaultValue: defaultValue.map(Double.init),
            format: format,
            accent: accent,
            size: size
        )
        .onAppear { displayValue = Double(getValue()) }
        // Poll the engine value so external changes (MIDI, scenes) reflect.
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            let v = Double(getValue())
            if abs(v - displayValue) > 0.001 { displayValue = v }
        }
    }
}
