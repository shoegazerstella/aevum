// SetlistView.swift — Similarity-suggested setlists, Aevum-styled.
// Three modes (smooth/contrast/cluster) with adjacent-similarity dots.

import SwiftUI

struct SetlistView: View {
    @EnvironmentObject var controller: EngineController
    @State private var mode: SetlistSuggester.Mode = .smooth
    @State private var orderedLoops: [Loop] = []
    @State private var adjacentSims: [Float] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: AevumSpacing.s) {
                Text("Setlist").font(AevumFont.headline).foregroundStyle(AevumColors.text)
                Spacer()
                modePicker
                Button(action: regenerate) {
                    Label("Regenerate", systemImage: "arrow.triangle.2.circlepath")
                        .font(AevumFont.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(AevumColors.amber.opacity(0.18)))
                        .foregroundStyle(AevumColors.amber)
                        .overlay(Capsule().strokeBorder(AevumColors.amber.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(AevumSpacing.m)

            if orderedLoops.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(orderedLoops.enumerated()), id: \.element.id) { idx, loop in
                            HStack(spacing: AevumSpacing.s) {
                                Text("\(idx + 1)")
                                    .font(AevumFont.mono).foregroundStyle(AevumColors.textFaint)
                                    .frame(width: 22)
                                Rectangle()
                                    .fill(Color(hexString: loop.color) ?? .gray)
                                    .frame(width: 3, height: 26)
                                    .cornerRadius(1.5)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(loop.name).font(AevumFont.caption).foregroundStyle(AevumColors.text)
                                    Text("\(loop.bars)b · \(String(format: "%.0f", loop.bpm)) BPM")
                                        .font(AevumFont.micro).foregroundStyle(AevumColors.textFaint)
                                }
                                Spacer()
                                if idx > 0 && idx - 1 < adjacentSims.count {
                                    SimDot(sim: adjacentSims[idx - 1])
                                }
                            }
                            .padding(.horizontal, AevumSpacing.m).padding(.vertical, 7)
                            if idx < orderedLoops.count - 1 {
                                Divider().overlay(AevumColors.divider).padding(.leading, AevumSpacing.l + 12)
                            }
                        }
                    }
                }
            }
        }
        .background(AevumColors.panel)
        .onAppear { regenerate() }
        .onChange(of: mode) { _ in regenerate() }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(SetlistSuggester.Mode.allCases, id: \.self) { m in
                let isOn = mode == m
                Button(action: { mode = m }) {
                    Text(m.rawValue)
                        .font(AevumFont.caption)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .foregroundStyle(isOn ? AevumColors.amber : AevumColors.textFaint)
                        .background(
                            RoundedRectangle(cornerRadius: AevumRadius.small)
                                .fill(isOn ? AevumColors.amber.opacity(0.15) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: AevumRadius.small).fill(AevumColors.panelRaised))
    }

    private var emptyState: some View {
        VStack(spacing: AevumSpacing.s) {
            Spacer()
            Image(systemName: "arrow.right.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(AevumColors.textFaint)
            Text("No setlist yet").font(AevumFont.caption).foregroundStyle(AevumColors.textDim)
            Text("Import songs, then Regenerate.").font(AevumFont.micro).foregroundStyle(AevumColors.textFaint)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func regenerate() {
        let suggester = SetlistSuggester()
        let sim = SimilarityEngine()
        let matrix = sim.similarityMatrix(loops: controller.loops)
        orderedLoops = suggester.suggest(loops: controller.loops, mode: mode, matrix: matrix)
        var sims: [Float] = []
        for i in 1..<orderedLoops.count {
            sims.append(sim.cosine(orderedLoops[i - 1].embedding, orderedLoops[i].embedding))
        }
        adjacentSims = sims
    }
}

private struct SimDot: View {
    let sim: Float
    var body: some View {
        VStack(spacing: 1) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(String(format: "%.2f", sim))
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(AevumColors.textFaint)
        }
    }
    private var color: Color {
        if sim > 0.7 { return AevumColors.good }
        if sim > 0.4 { return AevumColors.amber }
        return AevumColors.danger
    }
}
