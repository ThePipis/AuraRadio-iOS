import SwiftUI
import AVKit

struct AirPlayPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.activeTintColor = UIColor(Color.neonCyan)
        picker.tintColor = UIColor.white
        picker.prioritizesVideoDevices = false
        return picker
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

struct FullPlayerView: View {
    @ObservedObject var player = RadioPlayerService.shared
    @ObservedObject var store = FavoritesStore.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize

    var isLandscape: Bool {
        vSize == .compact
    }

    var body: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()

            if let station = player.currentStation {
                VStack(spacing: 0) {
                    // Top Bar
                    HStack {
                        Button(action: { dismiss() }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Text(station.streamFormatBadge)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(Color.darkSurfaceVariant)
                            .clipShape(Capsule())
                        Spacer()
                        AirPlayPickerButton()
                            .frame(width: 32, height: 32)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, isLandscape ? 8 : 14)

                    if isLandscape {
                        HStack(spacing: 24) {
                            stationInfoSection(station: station)
                                .frame(maxWidth: .infinity)
                            controlsSection(station: station)
                                .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    } else {
                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                stationInfoSection(station: station)
                                controlsSection(station: station)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func stationInfoSection(station: Station) -> some View {
        VStack(spacing: 12) {
            Text(station.name)
                .font(.system(size: isLandscape ? 20 : 22, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)

            AsyncImage(url: URL(string: station.favicon)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().padding(14)
                default:
                    Image(systemName: "radio.fill")
                        .font(.system(size: 64))
                        .foregroundColor(.deepViolet)
                }
            }
            .frame(width: isLandscape ? 160 : 220, height: isLandscape ? 160 : 220)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(radius: 8)

            Text(station.subtitleInfo)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Color.darkSurfaceVariant)
                .clipShape(Capsule())

            if player.isAdPlaying {
                Text("🛡️ Omitiendo anuncio del proveedor…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentRed)
            } else if !player.liveTitle.isEmpty && player.liveTitle != station.name {
                Text(player.liveTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.neonCyan)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func controlsSection(station: Station) -> some View {
        let isFav = store.isFavorite(station.id)

        VStack(spacing: isLandscape ? 14 : 20) {
            // Volume Slider
            HStack(spacing: 10) {
                Image(systemName: "speaker.fill")
                    .foregroundColor(.textSecondary)
                Slider(value: Binding(
                    get: { Double(player.volume) },
                    set: { player.setVolume(Float($0)) }
                ), in: 0...1)
                .tint(.textPrimary)
                Image(systemName: "speaker.wave.3.fill")
                    .foregroundColor(.textSecondary)
            }

            // Status + Blacklist + Stop
            HStack {
                Text(player.isLoading ? "Conectando…" : (player.errorMessage ?? "En Vivo • HD"))
                    .font(.system(size: 12))
                    .foregroundColor(player.errorMessage != nil ? .accentRed : .textSecondary)
                Spacer()
                Button(action: {
                    player.blacklistCurrentStation()
                }) {
                    Label("Lista Negra", systemImage: "nosign")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentRed)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentRed.opacity(0.15))
                        .clipShape(Capsule())
                }
                Button(action: {
                    player.stop()
                    dismiss()
                }) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.textSecondary)
                        .padding(8)
                }
            }

            // Main Playback Controls
            HStack(spacing: 28) {
                Button(action: { store.toggleFavorite(station) }) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 24))
                        .foregroundColor(isFav ? .accentRed : .textPrimary)
                }

                Button(action: { player.playPrev() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.textPrimary)
                }

                Button(action: { player.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(Color.darkSurfaceVariant)
                            .frame(width: 70, height: 70)
                        if player.isLoading {
                            ProgressView().tint(.neonCyan)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 32))
                                .foregroundColor(.textPrimary)
                        }
                    }
                }

                Button(action: { player.playNext() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.textPrimary)
                }

                AirPlayPickerButton()
                    .frame(width: 28, height: 28)
            }
        }
    }
}
