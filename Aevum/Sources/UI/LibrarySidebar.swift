// LibrarySidebar.swift — Songs list, Aevum-styled.

import SwiftUI

struct LibrarySidebar: View {
    @EnvironmentObject var controller: EngineController
    @Binding var selectedSongId: Int64?

    var body: some View {
        ScrollView {
            if controller.songs.isEmpty {
                VStack(spacing: AevumSpacing.s) {
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(AevumColors.textFaint)
                    Text("Library empty").font(AevumFont.caption).foregroundStyle(AevumColors.textFaint)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                VStack(spacing: 2) {
                    ForEach(controller.songs) { song in
                        SidebarRow(song: song,
                                   loopCount: controller.loops.filter { $0.songId == song.id }.count,
                                   isSelected: selectedSongId == song.id)
                            .onTapGesture { selectedSongId = song.id }
                            .contextMenu {
                                Button(role: .destructive) {
                                    controller.deleteSong(song)
                                    if selectedSongId == song.id {
                                        selectedSongId = nil
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(AevumSpacing.xs)
            }
        }
    }
}

private struct SidebarRow: View {
    let song: Song
    let loopCount: Int
    let isSelected: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(song.name)
                .font(AevumFont.body)
                .foregroundStyle(isSelected ? AevumColors.text : AevumColors.textDim)
                .lineLimit(1)
            HStack(spacing: AevumSpacing.s) {
                Label(String(format: "%.0f", song.bpm), systemImage: "metronome")
                    .labelStyle(.titleAndIcon).font(AevumFont.micro)
                    .foregroundStyle(AevumColors.amber.opacity(0.8))
                Text("\(loopCount) loops")
                    .font(AevumFont.micro).foregroundStyle(AevumColors.textFaint)
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Capsule().fill(AevumColors.panelRaised))
            }
        }
        .padding(.horizontal, AevumSpacing.s).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AevumRadius.small)
                .fill(isSelected ? AevumColors.amber.opacity(0.1) : .clear)
        )
    }
}
