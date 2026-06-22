// ParamPanel.swift — Live parameter controls, Aevum-styled.
// Tabbed (Essentials / Advanced) so the panel fits the right column
// without scrolling. Each section has a help popover and a one-line
// subtitle; each slider has a hover tooltip.

import SwiftUI

struct ParamPanel: View {
    @EnvironmentObject var controller: EngineController
    @State private var selectedTab: Tab = .essentials

    enum Tab: String, CaseIterable, Identifiable {
        case essentials = "Essentials"
        case advanced = "Advanced"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider().overlay(AevumColors.divider)
            ScrollView {
                VStack(alignment: .leading, spacing: AevumSpacing.l) {
                    switch selectedTab {
                    case .essentials:
                        blendSection
                        samplingSection
                    case .advanced:
                        guidanceSection
                        outputSection
                        performanceSection
                    }
                }
                .padding(AevumSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
        }
        .background(AevumColors.panel)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                let isOn = selectedTab == tab
                Button(action: { selectedTab = tab }) {
                    Text(tab.rawValue)
                        .font(AevumFont.caption)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(isOn ? AevumColors.amber : AevumColors.textFaint)
                        .background(
                            Rectangle().fill(isOn ? AevumColors.amber.opacity(0.10) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AevumSpacing.s)
        .padding(.top, AevumSpacing.s)
        .background(AevumColors.panel)
    }

    // MARK: - Sections

    private var blendSection: some View {
        Section(title: "Blend",
                subtitle: "morph between loaded clips",
                help: "Per-slot weights for morphing between loaded clips. 0 = silent, 1 = solo. Weights should sum to 1 — click Normalize if they don't. Double-click a clip in the grid to add it to the blend.") {
            ForEach(0..<6, id: \.self) { i in
                HStack(spacing: AevumSpacing.s) {
                    Text("S\(i)").font(AevumFont.mono).foregroundStyle(AevumColors.textDim)
                        .frame(width: 24, alignment: .leading)
                    GeometryReader { geo in
                        let v = CGFloat(controller.blendWeights[i])
                        ZStack(alignment: .leading) {
                            Capsule().fill(AevumColors.panelRaised).frame(height: 3)
                            Capsule()
                                .fill(LinearGradient(colors: [AevumColors.amber.opacity(0.7), AevumColors.amber],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: geo.size.width * v, height: 3)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { d in
                            let n = max(0, min(1, d.location.x / geo.size.width))
                            controller.setBlendWeight(i, Float(n))
                        })
                    }
                    .frame(height: 18)
                    Text(String(format: "%.2f", controller.blendWeights[i]))
                        .font(AevumFont.mono).foregroundStyle(AevumColors.text)
                        .frame(width: 36, alignment: .trailing)
                }
                .help("Blend weight for slot \(i). 0 = silent, 1 = solo. Drag to adjust.")
            }
            Button("Normalize") {
                let s = controller.blendWeights.reduce(0, +)
                if s > 0 { for i in 0..<6 { controller.setBlendWeight(i, controller.blendWeights[i] / s) } }
            }
            .font(AevumFont.caption)
            .buttonStyle(.plain)
            .foregroundStyle(AevumColors.textDim)
            .help("Scale all weights so they sum to 1")
        }
    }

    private var samplingSection: some View {
        Section(title: "Sampling",
                subtitle: "how the next token is chosen",
                help: "How the model picks each token. Temperature = randomness (low = predictable, high = wild). Top-K = how many candidates are considered. Seed Rotate shifts the random seed each frame for variation.") {
            AevumSlider(label: "Temperature", value: binding(.temperature, 0.1, 1.5),
                        range: 0.1...1.5, format: "%.2f")
                .help("Randomness of token sampling. 0.1 = near-deterministic, 1.5 = chaotic")
            AevumSlider(label: "Top-K", value: binding(.topK, 1, 200),
                        range: 1...200, format: "%.0f", accent: AevumColors.cyan)
                .help("Number of candidate tokens considered per step. Lower = faster, safer")
            AevumSlider(label: "Seed Rotate", value: binding(.seedRotation, 0, 100),
                        range: 0...100, format: "%.0f", accent: AevumColors.cyan)
                .help("Shift the random seed every N frames for variation. 0 = off")
        }
    }

    private var guidanceSection: some View {
        Section(title: "Guidance",
                subtitle: "how strongly to follow the prompt",
                help: "Classifier-free guidance — how strongly the model sticks to the prompt. Style = overall musical style. Notes = melodic content. Drums = drum patterns. Unmask = how many fine RVQ layers are revealed to the transformer.") {
            AevumSlider(label: "Style", value: binding(.cfgMusiccoca, 0, 10),
                        range: 0...10, format: "%.1f")
                .help("How strongly to follow the clip/style prompt. Higher = more obedient, less creative")
            AevumSlider(label: "Notes", value: binding(.cfgNotes, 0, 10),
                        range: 0...10, format: "%.1f", accent: AevumColors.cyan)
                .help("How strongly to follow melodic prompts")
            AevumSlider(label: "Drums", value: binding(.cfgDrums, 0, 10),
                        range: 0...10, format: "%.1f", accent: AevumColors.cyan)
                .help("How strongly to follow drum prompts")
            AevumSlider(label: "Unmask", value: binding(.unmaskWidth, 0, 12),
                        range: 0...12, format: "%.0f", accent: AevumColors.cyan)
                .help("How many fine RVQ levels are revealed. 0 = coarse only, 12 = full detail")
        }
    }

    private var outputSection: some View {
        Section(title: "Output",
                subtitle: "volume, drums, gating",
                help: "Volume (dB), Drumless (strip drums from generation), MIDI Gate (silence audio when no MIDI notes held), Bypass (pass-through). Onset mode controls note attack timing.") {
            AevumSlider(label: "Volume", value: binding(.volumeDb, -40, 6),
                        range: -40...6, format: "%.1f")
                .help("Output gain in dB. 0 = unity, -40 = near-silent")
            AevumToggle(label: "Drumless", isOn: binding(.drumless, 0, 1))
                .help("Strip drums from generation")
            AevumToggle(label: "MIDI Gate", isOn: binding(.midiGate, 0, 1))
                .help("Silence audio when no MIDI notes are held")
            AevumToggle(label: "Bypass", isOn: binding(.bypass, 0, 1))
                .help("Pass-through — bypass the engine entirely")
            onsetPicker
                .help("Auto-Strum: model places note onsets. Manual: you control attack timing")
        }
    }

    private var performanceSection: some View {
        Section(title: "Performance",
                subtitle: "buffer, quality, health",
                help: "Buffer size = latency vs resilience tradeoff. Quality preset adjusts Top-K + CFG for faster/slower generation. RTF must stay <1.0 to avoid corruption. Dropped frames = audio underruns already happened.") {
            qualityPicker
                .help("Preset adjusts Top-K + CFG. Performance = faster, Quality = richer")
            AevumSlider(label: "Buffer",
                        value: Binding(
                            get: { Double(controller.bufferSize) },
                            set: { controller.bufferSize = UInt($0) }),
                        range: 2048...8192, format: "%.0f",
                        accent: AevumColors.cyan)
                .help("Ring buffer size in samples. Larger = more latency, more resilience to GPU hiccups")
            rtfRow
            bufferFillRow
            if controller.metrics.droppedFrames > 0 {
                HStack(spacing: AevumSpacing.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(AevumColors.danger)
                    Text("\(controller.metrics.droppedFrames) dropped frames")
                        .font(AevumFont.caption)
                        .foregroundStyle(AevumColors.danger)
                    Spacer()
                    Button("Reset") { controller.bridge.resetDroppedFrames() }
                        .font(AevumFont.micro)
                        .buttonStyle(.plain)
                        .foregroundStyle(AevumColors.textDim)
                }
            }
        }
    }

    private var qualityPicker: some View {
        HStack(spacing: AevumSpacing.s) {
            Text("Quality").font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
                .frame(width: 96, alignment: .leading)
            Picker("", selection: $controller.qualityPreset) {
                ForEach(EngineController.QualityPreset.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    /// Real-time factor readout: <1.0 = headroom (green), ~1.0 = edge (amber),
    /// >1.0 = underrun territory (red). 40ms budget per frame at 25 Hz.
    private var rtfRow: some View {
        let rtf = controller.realTimeFactor
        let color: Color = rtf > 1.0 ? AevumColors.danger
                        : rtf > 0.85 ? AevumColors.amber
                        : AevumColors.good
        return HStack(spacing: AevumSpacing.s) {
            Text("RTF").font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
                .frame(width: 96, alignment: .leading)
            Text(String(format: "%.2f×", rtf))
                .font(AevumFont.monoBold)
                .foregroundStyle(color)
                .frame(width: 44, alignment: .trailing)
            Text(String(format: "%.1fms", controller.metrics.totalMs))
                .font(AevumFont.mono)
                .foregroundStyle(AevumColors.textFaint)
            Spacer()
        }
        .help("Real-time factor: <1.0 = headroom, >1.0 = underrun risk (40ms budget per frame)")
    }

    /// Ring buffer fill indicator — how much audio is buffered ahead.
    private var bufferFillRow: some View {
        let avail = Double(controller.metrics.bufferAvailable)
        let cap = Double(controller.metrics.bufferCapacity)
        let pct = cap > 0 ? avail / cap : 0
        let color: Color = pct < 0.2 ? AevumColors.danger
                        : pct < 0.5 ? AevumColors.amber
                        : AevumColors.good
        return HStack(spacing: AevumSpacing.s) {
            Text("Buffer").font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
                .frame(width: 96, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(AevumColors.panelRaised).frame(height: 3)
                    Capsule().fill(color)
                        .frame(width: geo.size.width * CGFloat(pct), height: 3)
                }
            }
            .frame(height: 18)
            Text(String(format: "%.0f%%", pct * 100))
                .font(AevumFont.mono)
                .foregroundStyle(color)
                .frame(width: 44, alignment: .trailing)
        }
        .help("Ring buffer fill — low = underrun risk")
    }

    private var onsetPicker: some View {
        HStack(spacing: AevumSpacing.s) {
            Text("Onset").font(AevumFont.caption).foregroundStyle(AevumColors.textDim).frame(width: 96, alignment: .leading)
            Picker("", selection: Binding(
                get: { controller.paramSnapshot.onsetMode },
                set: { controller.applyParam(.onsetMode, value: $0 == .unmasked ? 1 : 0) }
            )) {
                Text("Auto-Strum").tag(XFOnsetMode.masked)
                Text("Manual").tag(XFOnsetMode.unmasked)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    // Bindings bridge AevumSlider/AevumToggle (Double/Bool) ↔ EngineController (Float).
    private func binding(_ p: XFParam, _ lo: Float, _ hi: Float) -> Binding<Double> {
        Binding(get: { Double(currentValue(p)) },
                set: { controller.applyParam(p, value: Float($0)) })
    }
    private func binding(_ p: XFParam, _ lo: Float, _ hi: Float) -> Binding<Bool> {
        Binding(get: { currentValue(p) > 0.5 },
                set: { controller.applyParam(p, value: $0 ? 1 : 0) })
    }
    private func currentValue(_ p: XFParam) -> Float {
        let s = controller.paramSnapshot
        switch p {
        case .temperature:  return s.temperature
        case .topK:          return s.topK
        case .cfgMusiccoca:  return s.cfgMusiccoca
        case .cfgNotes:      return s.cfgNotes
        case .cfgDrums:      return s.cfgDrums
        case .unmaskWidth:   return s.unmaskWidth
        case .seedRotation:  return s.seedRotation
        case .volumeDb:      return s.volumeDb
        case .drumless:      return s.drumless ? 1 : 0
        case .midiGate:      return s.midiGate ? 1 : 0
        case .bypass:        return s.bypass ? 1 : 0
        default:             return 0
        }
    }
}

// MARK: - Section container with help popover + subtitle

private struct Section<Content: View>: View {
    let title: String
    let subtitle: String
    let help: String
    @State private var showHelp = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AevumSpacing.s) {
            HStack(alignment: .firstTextBaseline, spacing: AevumSpacing.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(AevumColors.textFaint)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(AevumColors.textFaint.opacity(0.7))
                }
                Spacer()
                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AevumColors.textDim)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showHelp) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.headline)
                        Text(help)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 260)
                    .padding(12)
                }
            }
            content()
        }
    }
}
