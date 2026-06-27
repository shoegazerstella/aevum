// MacroKnobs.swift — A row of 4 always-visible rotary knobs for the
// most live-touched parameters: Temperature (chaos), Style (CFG MusicCoCa),
// Chaos (seed rotation), and Drums (on/off toggle styled as a knob).
// Lives above the prompt surface in both standard and focused layouts.

import SwiftUI

struct MacroKnobs: View {
    @EnvironmentObject var controller: EngineController

    var body: some View {
        HStack(spacing: AevumSpacing.l) {
            KnobFloat(
                label: "TEMP",
                getValue: { controller.paramSnapshot.temperature },
                setValue: { controller.applyParam(.temperature, value: $0) },
                range: 0.1...1.5,
                defaultValue: 1.0,
                format: "%.2f",
                accent: AevumColors.amber
            )
            KnobFloat(
                label: "STYLE",
                getValue: { controller.paramSnapshot.cfgMusiccoca },
                setValue: { controller.applyParam(.cfgMusiccoca, value: $0) },
                range: 0...10,
                defaultValue: 3.0,
                format: "%.1f",
                accent: AevumColors.cyan
            )
            KnobFloat(
                label: "CHAOS",
                getValue: { controller.paramSnapshot.seedRotation },
                setValue: { controller.applyParam(.seedRotation, value: $0) },
                range: 0...100,
                defaultValue: 0,
                format: "%.0f",
                accent: AevumColors.amber
            )
            // Drums toggle as a 2-position knob (0 = OFF/drumless, 1 = ON).
            KnobFloat(
                label: "DRUMS",
                getValue: { controller.paramSnapshot.drumless ? 0 : 1 },
                setValue: { controller.applyParam(.drumless, value: $0 > 0.5 ? 0 : 1) },
                range: 0...1,
                defaultValue: 1,
                format: "%.0f",
                accent: AevumColors.cyan
            )
        }
        .padding(.horizontal, AevumSpacing.m)
        .padding(.vertical, AevumSpacing.s)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.medium)
                .fill(AevumColors.panel.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AevumRadius.medium)
                .strokeBorder(AevumColors.divider, lineWidth: 1)
        )
    }
}
