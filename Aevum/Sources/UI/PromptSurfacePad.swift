// PromptSurfacePad.swift — 2D blend surface (the hero control).
// Drag the cursor to morph between nearby clip slots (inverse-distance
// weighted). Drag slot dots to rearrange. Center reset button snaps
// back. Each loaded clip label follows its dot.
//
// The cursor + slot positions are @Published on EngineController so
// scenes can capture and restore the full prompt-surface state. The
// cursor leaves a fading trail so morph motion is visible during a set;
// connection lines from cursor → slot are drawn in the blend-axis color
// (amber→cyan) and thicken with their blend weight.

import SwiftUI

struct PromptSurfacePad: View {
    @EnvironmentObject var controller: EngineController
    @State private var pulse: Bool = false
    @State private var showHelp: Bool = false
    @State private var trail: [CGPoint] = []

    // Cursor + slot positions are read from / written to the controller.
    // Local @State copies would break scene capture/restore.
    private var cursor: CGPoint { controller.cursorPosition }
    private var slotPositions: [Int: CGPoint] { controller.slotPositions }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Prompt Surface").font(AevumFont.headline).foregroundStyle(AevumColors.text)
                    Text("Drag cursor to blend · drag dots to arrange")
                        .font(AevumFont.micro).foregroundStyle(AevumColors.textFaint)
                }
                Spacer()
                HStack(spacing: 4) {
                    Button {
                        showHelp.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AevumColors.textDim)
                            .frame(width: 24, height: 24)
                    }.buttonStyle(.plain)
                        .popover(isPresented: $showHelp) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("How it works").font(.headline)
                                Text("Each dot is a loaded clip. Drag the cursor around the surface — the engine blends between nearby clips based on distance. The closer the cursor is to a dot, the more that clip influences the sound.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("Drag individual dots to rearrange the space to your liking. Tap the center reset button to snap the cursor back to center. Arrow keys nudge the cursor for fine control. Single-click a clip in the grid to solo it; double-click to add/remove it from the blend.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 260)
                            .padding(12)
                        }
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            controller.cursorPosition = CGPoint(x: 0.5, y: 0.5)
                        }
                        controller.updatePromptSurface(cursor: controller.cursorPosition,
                                                       slotPositions: controller.slotPositions)
                    } label: {
                        Image(systemName: "scope")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AevumColors.textDim)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(AevumColors.panelRaised))
                    }.buttonStyle(.plain)
                }
            }
            .padding(AevumSpacing.m)

            GeometryReader { geo in
                let size = min(geo.size.width, geo.size.height) - 16

                ZStack {
                    // Blend field — subtle radial gradient with a faint
                    // moving glow tied to the cursor for a "live field" feel.
                    RoundedRectangle(cornerRadius: AevumRadius.medium)
                        .fill(
                            RadialGradient(colors: [
                                AevumColors.panelRaised.opacity(0.6),
                                AevumColors.bgDeep
                            ], center: .center, startRadius: 10, endRadius: size * 0.6)
                        )
                        .frame(width: size, height: size)

                    // Connection lines from cursor to each active slot.
                    // Thickness + opacity scale with blend weight; color
                    // follows the blend axis (amber→cyan) by slot index.
                    Canvas { ctx, sz in
                        for slot in 0..<6 where controller.blendWeights[slot] > 0.01 {
                            let pos = slotPositions[slot] ?? controller.defaultSlotPosition(slot)
                            let p = CGPoint(x: pos.x * sz.width, y: pos.y * sz.height)
                            let c = CGPoint(x: cursor.x * sz.width, y: cursor.y * sz.height)
                            let w = CGFloat(controller.blendWeights[slot])
                            var line = Path()
                            line.move(to: c)
                            line.addLine(to: p)
                            let t = Double(slot) / 5.0
                            ctx.stroke(line,
                                       with: .color(AevumColors.blendAxis(at: t).opacity(Double(w * 0.55))),
                                       lineWidth: 1 + 2 * w)
                        }
                    }
                    .frame(width: size, height: size)

                    // Cursor trail — fading dots of the last N positions.
                    Canvas { ctx, sz in
                        let n = trail.count
                        for (i, pt) in trail.enumerated() {
                            let age = CGFloat(n - i) / CGFloat(max(1, n))
                            let alpha = (1 - age) * 0.35
                            let r = 2 + (1 - age) * 3
                            let p = CGPoint(x: pt.x * sz.width, y: pt.y * sz.height)
                            let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                            ctx.fill(Path(ellipseIn: rect),
                                     with: .color(AevumColors.amber.opacity(Double(alpha))))
                        }
                    }
                    .frame(width: size, height: size)
                    .allowsHitTesting(false)

                    // Slot dots — sized/glowing by blend weight, colored
                    // along the blend axis so the morph position is readable.
                    ForEach(0..<6, id: \.self) { slot in
                        let w = controller.blendWeights[slot]
                        if slotPositions[slot] != nil || controller.slotLoopIds[slot] != nil {
                            let pos = slotPositions[slot] ?? controller.defaultSlotPosition(slot)
                            SlotDot(slot: slot,
                                    weight: w,
                                    label: controller.slotLabels[slot])
                                .position(x: pos.x * size, y: pos.y * size)
                                .gesture(
                                    DragGesture()
                                        .onChanged { v in
                                            controller.slotPositions[slot] = CGPoint(
                                                x: max(0, min(1, v.location.x / size)),
                                                y: max(0, min(1, v.location.y / size)))
                                            controller.updatePromptSurface(
                                                cursor: controller.cursorPosition,
                                                slotPositions: controller.slotPositions)
                                        }
                                )
                                .contextMenu {
                                    Button(role: .destructive) {
                                        controller.clearSlot(slot)
                                    } label: {
                                        Label("Remove from slot", systemImage: "xmark.circle")
                                    }
                                }
                        }
                    }

                    // Cursor — glowing orb with breathing ring
                    ZStack {
                        Circle()
                            .fill(AevumColors.amber)
                            .frame(width: 12, height: 12)
                            .shadow(color: AevumColors.amber.opacity(0.9), radius: 16)
                        Circle()
                            .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                            .frame(width: 24, height: 24)
                            .scaleEffect(pulse ? 1.15 : 0.85)
                        Circle()
                            .strokeBorder(AevumColors.amber.opacity(0.3), lineWidth: 1)
                            .frame(width: 36, height: 36)
                            .scaleEffect(pulse ? 1.25 : 0.95)
                            .opacity(pulse ? 0.0 : 0.5)
                    }
                    .position(x: cursor.x * size, y: cursor.y * size)
                    .onAppear { withAnimation(AevumMotion.glow) { pulse = true } }
                }
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: AevumRadius.medium)
                        .fill(AevumColors.bgDeep)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AevumRadius.medium)
                        .strokeBorder(AevumColors.divider, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AevumRadius.medium))
                .padding(.horizontal, AevumSpacing.m)
                .padding(.bottom, AevumSpacing.m)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let p = CGPoint(
                                x: max(0, min(1, v.location.x / size)),
                                y: max(0, min(1, v.location.y / size)))
                            controller.cursorPosition = p
                            // Append to trail (cap length).
                            trail.append(p)
                            if trail.count > 24 { trail.removeFirst(trail.count - 24) }
                            controller.updatePromptSurface(
                                cursor: p,
                                slotPositions: controller.slotPositions)
                        }
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(AevumColors.panel)
    }

    /// Nudge the cursor by a small delta (for arrow-key control). Public
    /// so ContentView's keyboard handler can call it.
    func nudgeCursor(dx: CGFloat, dy: CGFloat) {
        let p = CGPoint(
            x: max(0, min(1, controller.cursorPosition.x + dx)),
            y: max(0, min(1, controller.cursorPosition.y + dy)))
        controller.cursorPosition = p
        trail.append(p)
        if trail.count > 24 { trail.removeFirst(trail.count - 24) }
        controller.updatePromptSurface(cursor: p, slotPositions: controller.slotPositions)
    }
}

private struct SlotDot: View {
    let slot: Int
    let weight: Float
    let label: String?
    @State private var breathe: Bool = false

    var body: some View {
        let intensity = max(0.15, CGFloat(weight))
        let color = AevumColors.blendAxis(at: Double(slot) / 5.0)
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(color.opacity(Double(intensity)))
                    .frame(width: 16 + 12 * intensity, height: 16 + 12 * intensity)
                    .shadow(color: color.opacity(Double(intensity) * 0.7),
                            radius: 8 * intensity)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 16, height: 16)
                // Breathing outer ring for active slots.
                if weight > 0.01 {
                    Circle()
                        .strokeBorder(color.opacity(0.4), lineWidth: 1)
                        .frame(width: 26, height: 26)
                        .scaleEffect(breathe ? 1.2 : 0.95)
                        .opacity(breathe ? 0.0 : 0.6)
                        .onAppear { withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) { breathe = true } }
                }
                Text("\(slot)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(weight > 0.1 ? 0.95 : 0.4))
            }
            if let label {
                Text(label)
                    .font(AevumFont.micro)
                    .foregroundStyle(.white.opacity(Double(intensity) * 0.7 + 0.3))
                    .lineLimit(1)
                    .frame(maxWidth: 60)
            }
        }
    }
}
