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
    @Environment(\.verticalSizeClass) private var vSize
    @State private var showSleepTimer = false

    var isLandscape: Bool {
        vSize == .compact
    }

    var body: some View {
        ZStack {
            Color.darkBackground.ignoresSafeArea()

            if let station = player.currentStation {
                GeometryReader { geo in
                    let landscape = isLandscape || geo.size.width > geo.size.height
                    let artSize = landscape
                        ? min(geo.size.height * 0.48, geo.size.width * 0.28, 220)
                        : min(geo.size.width * 0.50, geo.size.height * 0.28, 220)

                    VStack(spacing: 0) {
                        // Top Bar
                        HStack {
                            Button(action: { dismiss() }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundColor(.textPrimary)
                                    .padding(6)
                            }
                            Spacer()
                            Text(station.streamFormatBadge)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.textPrimary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(Color.darkSurfaceVariant)
                                .clipShape(Capsule())
                            Spacer()
                            Button(action: { showSleepTimer = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 18))
                                    if player.sleepTimerRemainingMinutes > 0 {
                                        Text("\(player.sleepTimerRemainingMinutes)m")
                                            .font(.caption2.bold())
                                    }
                                }
                                .foregroundColor(player.sleepTimerRemainingMinutes > 0 ? .neonCyan : .textPrimary)
                                .padding(6)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, landscape ? 6 : 10)
                        .padding(.bottom, landscape ? 4 : 8)

                        if landscape {
                            HStack(spacing: 24) {
                                stationInfoSection(station: station, artSize: artSize, compact: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                controlsSection(station: station, compact: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                            .padding(.horizontal, 24)
                            .padding(.bottom, 12)
                        } else {
                            VStack(spacing: 0) {
                                Spacer(minLength: 4)
                                stationInfoSection(station: station, artSize: artSize, compact: false)
                                Spacer(minLength: 8)
                                controlsSection(station: station, compact: false)
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 22)
                            .padding(.bottom, 12)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .sheet(isPresented: $showSleepTimer) {
            SleepTimerSheet()
        }
    }

    @ViewBuilder
    private func stationInfoSection(station: Station, artSize: CGFloat, compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            Text(station.name)
                .font(.system(size: compact ? 18 : 21, weight: .bold))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            AsyncImage(url: URL(string: station.favicon)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit().padding(12)
                default:
                    Image(systemName: "radio.fill")
                        .font(.system(size: artSize * 0.35))
                        .foregroundColor(.deepViolet)
                }
            }
            .frame(width: artSize, height: artSize)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(radius: 8)

            Text(station.subtitleInfo)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.darkSurfaceVariant)
                .clipShape(Capsule())

            if !player.liveTitle.isEmpty && player.liveTitle != station.name {
                MarqueeBannerText(
                    text: "🎵 \(player.liveTitle)",
                    font: .system(size: 13, weight: .semibold),
                    color: .neonCyan
                )
                .frame(height: 22)
                .padding(.horizontal, 8)
            }
        }
    }

    @ViewBuilder
    private func controlsSection(station: Station, compact: Bool) -> some View {
        let isFav = store.isFavorite(station.id)

        VStack(spacing: compact ? 12 : 16) {
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
                        .padding(6)
                }
            }

            // Main Playback Controls
            HStack(spacing: 24) {
                Button(action: { store.toggleFavorite(station) }) {
                    Image(systemName: isFav ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(isFav ? .accentRed : .textPrimary)
                }

                Button(action: { player.playPrev() }) {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.textPrimary)
                }

                Button(action: { player.togglePlayPause() }) {
                    ZStack {
                        Circle()
                            .fill(Color.darkSurfaceVariant)
                            .frame(width: compact ? 58 : 66, height: compact ? 58 : 66)
                        if player.isLoading {
                            ProgressView().tint(.neonCyan)
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: compact ? 26 : 30))
                                .foregroundColor(.textPrimary)
                        }
                    }
                }

                Button(action: { player.playNext() }) {
                    Image(systemName: "forward.end.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.textPrimary)
                }

                AirPlayPickerButton()
                    .frame(width: 28, height: 28)
            }
        }
    }
}

struct MarqueeBannerText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var textWidth: CGFloat = 0
    @State private var startTime = Date()

    private let speed: CGFloat = 42.0 // px por segundo de derecha a izquierda
    private let gap: CGFloat = 56.0

    var body: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            let cycleDistance = max(textWidth, containerWidth) + gap

            TimelineView(.animation) { timeline in
                let elapsed = max(0, timeline.date.timeIntervalSince(startTime) - 1.0)
                let offset = -CGFloat(elapsed * Double(speed)).truncatingRemainder(dividingBy: cycleDistance)

                ZStack(alignment: .leading) {
                    HStack(spacing: gap) {
                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize(horizontal: true, vertical: false)
                            .background(
                                GeometryReader { textGeo in
                                    Color.clear
                                        .onAppear { textWidth = textGeo.size.width }
                                        .onChange(of: textGeo.size.width) { newW in
                                            textWidth = newW
                                        }
                                        .onChange(of: text) { _ in
                                            startTime = Date()
                                        }
                                }
                            )

                        Text(text)
                            .font(font)
                            .foregroundColor(color)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .offset(x: offset)
                }
                .frame(width: containerWidth, alignment: .leading)
                .clipped()
                .mask(
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1.0)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            }
        }
        .onChange(of: text) { _ in
            startTime = Date()
        }
    }
}
