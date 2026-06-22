// PromptSurfacePad.swift — 2D blend surface (the hero control).
// Drag the cursor to morph between nearby clip slots (inverse-distance
// weighted). Drag slot dots to rearrange. Center reset button snaps
// back. Each loaded clip label follows its dot.
//
// The cursor + slot positions are @Published on EngineController so
// scenes can capture and restore the full prompt-surface state.

import SwiftUI

struct PromptSurfacePad: View {
    @EnvironmentObject var controller: EngineController
    @State private var pulse: Bool = false
    @State private var showHelp: Bool = false

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
                                Text("Drag individual dots to rearrange the space to your liking. Tap the center reset button to snap the cursor back to center. Single-click a clip in the grid to solo it; double-click to add/remove it from the blend.")
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
                    // Blend field — subtle gradient, no distracting grid lines
                    RoundedRectangle(cornerRadius: AevumRadius.medium)
                        .fill(
                            RadialGradient(colors: [
                                AevumColors.panelRaised.opacity(0.6),
                                AevumColors.bgDeep
                            ], center: .center, startRadius: 10, endRadius: size * 0.6)
                        )
                        .frame(width: size, height: size)

                    // Connection lines from cursor to each active slot
                    Canvas { ctx, sz in
                        for slot in 0..<6 where controller.blendWeights[slot] > 0.01 {
                            let pos = slotPositions[slot] ?? controller.defaultSlotPosition(slot)
                            let p = CGPoint(x: pos.x * sz.width, y: pos.y * sz.height)
                            let c = CGPoint(x: cursor.x * sz.width, y: cursor.y * sz.height)
                            let w = CGFloat(controller.blendWeights[slot])
                            var line = Path()
                            line.move(to: c)
                            line.addLine(to: p)
                            ctx.stroke(line, with: .color(AevumColors.amber.opacity(w * 0.25)),
                                       lineWidth: 1)
                        }
                    }
                    .frame(width: size, height: size)

                    // Slot dots — sized/glowing by blend weight, with clip name labels.
                    // Show a dot for any slot that has a loop loaded, even at weight 0,
                    // so the user can see and drag it.
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

                    // Cursor — glowing orb
                    ZStack {
                        Circle()
                            .fill(AevumColors.amber)
                            .frame(width: 10, height: 10)
                            .shadow(color: AevumColors.amber.opacity(0.8), radius: 14)
                        Circle()
                            .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .scaleEffect(pulse ? 1.12 : 0.88)
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
                            controller.cursorPosition = CGPoint(
                                x: max(0, min(1, v.location.x / size)),
                                y: max(0, min(1, v.location.y / size)))
                            controller.updatePromptSurface(
                                cursor: controller.cursorPosition,
                                slotPositions: controller.slotPositions)
                        }
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .background(AevumColors.panel)
    }
}

private struct SlotDot: View {
    let slot: Int
    let weight: Float
    let label: String?

    var body: some View {
        let intensity = max(0.15, CGFloat(weight))
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(AevumColors.amber.opacity(Double(intensity)))
                    .frame(width: 14 + 10 * intensity, height: 14 + 10 * intensity)
                    .shadow(color: AevumColors.amber.opacity(Double(intensity) * 0.6),
                            radius: 6 * intensity)
                Circle()
                    .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 14, height: 14)
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
