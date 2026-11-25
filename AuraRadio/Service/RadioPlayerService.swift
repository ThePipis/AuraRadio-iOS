import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine

final class RadioPlayerService: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = RadioPlayerService()

    @Published var currentStation: Station?
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var liveTitle: String = ""
    @Published var isAdPlaying: Bool = false
    @Published var volume: Float = 1.0
    @Published var errorMessage: String?

    var playlist: [Station] = []
    private var player: AVPlayer?
    private var playerItemObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var pausedAtTimestamp: Date?
    private var cachedArtworkImage: UIImage?
    private var lastArtworkUrl: String = ""

    private let adKeywords = [
        "ad:", "advertisement", "publicidad", "comercial", "anuncio",
        "adswizz", "triton", "instream", "targetspot", "promo", "sponsor"
    ]

    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        detectGeoCountry()

        if let last = FavoritesStore.shared.getLastPlayedStation(),
           !FavoritesStore.shared.blacklistedIds.contains(last.id) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.playStation(last)
            }
        }
    }

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [.allowAirPlay])
            try session.setActive(true)
        } catch {
            print("[RadioPlayerService] AudioSession error: \(error)")
        }
    }

    private func setupRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.resumeOrReconnect()
            return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.playNext()
            return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.playPrev()
            return .success
        }
    }

    func detectGeoCountry() {
        guard let url = URL(string: "https://ipwho.is/?fields=country_code") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 2.5
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let code = json["country_code"] as? String, code.count == 2 {
                DispatchQueue.main.async {
                    FavoritesStore.shared.setDetectedCountryIso(code)
                }
            } else if FavoritesStore.shared.detectedCountryIso.isEmpty {
                let fallback = Locale.current.region?.identifier ?? "US"
                DispatchQueue.main.async {
                    FavoritesStore.shared.setDetectedCountryIso(fallback)
                }
            }
        }.resume()
    }

    func playStation(_ station: Station, list: [Station]? = nil) {
        let blackIds = FavoritesStore.shared.blacklistedIds
        if let list = list, !list.isEmpty {
            self.playlist = list.filter { !blackIds.contains($0.id) }
        } else if self.playlist.isEmpty {
            let favs = FavoritesStore.shared.favorites.filter { !blackIds.contains($0.id) }
            if favs.contains(where: { $0.id == station.id }) {
                self.playlist = favs
            } else {
                let iso = FavoritesStore.shared.detectedCountryIso
                self.playlist = VRadioDatabase.shared.getPopularStationsByCountryIso(iso, limit: 60)
                    .filter { !blackIds.contains($0.id) }
            }
        }

        let cleanUrlStr = VRadioDatabase.normalizeStreamUrl(station.url)
        guard let url = URL(string: cleanUrlStr) else {
            errorMessage = "URL de emisora inválida"
            return
        }

        FavoritesStore.shared.addRecentStation(station.id)
        FavoritesStore.shared.saveLastPlayedStation(station)
        if !station.country.isEmpty {
            FavoritesStore.shared.setLastPlayedCountry(station.country)
        }

        pausedAtTimestamp = nil
        currentStation = station
        isLoading = true
        isPlaying = true
        isAdPlaying = false
        liveTitle = station.name
        errorMessage = nil

        var headers: [String: String] = [
            "User-Agent": station.streamUserAgent.isEmpty ? "VRadio/2.0 (iOS)" : station.streamUserAgent
        ]
        if !station.streamReferer.isEmpty {
            headers["Referer"] = station.streamReferer
        }

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)

        let metadataOutput = AVPlayerItemMetadataOutput(identifiers: nil)
        metadataOutput.setDelegate(self, queue: DispatchQueue.main)
        item.add(metadataOutput)

        playerItemObserver?.invalidate()
        timeControlObserver?.invalidate()

        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] playerItem, _ in
            DispatchQueue.main.async {
                switch playerItem.status {
                case .readyToPlay:
                    self?.isLoading = false
                    self?.errorMessage = nil
                    self?.updateNowPlayingInfo()
                case .failed:
                    self?.isLoading = false
                    self?.isPlaying = false
                    self?.errorMessage = playerItem.error?.localizedDescription ?? "No se pudo conectar"
                    self?.updateNowPlayingInfo()
                default:
                    break
                }
            }
        }

        if player == nil {
            player = AVPlayer(playerItem: item)
        } else {
            player?.replaceCurrentItem(with: item)
        }

        player?.volume = isAdPlaying ? 0.0 : volume

        timeControlObserver = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] avPlayer, _ in
            DispatchQueue.main.async {
                switch avPlayer.timeControlStatus {
                case .playing:
                    self?.isPlaying = true
                    self?.isLoading = false
                case .paused:
                    self?.isPlaying = false
                    self?.isLoading = false
                case .waitingToPlayAtSpecifiedRate:
                    self?.isLoading = true
                @unknown default:
                    break
                }
                self?.updateNowPlayingInfo()
            }
        }

        player?.play()
        loadArtworkIfNeeded(urlStr: station.favicon)
        updateNowPlayingInfo()
    }

    func pause() {
        pausedAtTimestamp = Date()
        player?.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func resumeOrReconnect() {
        guard let st = currentStation ?? FavoritesStore.shared.getLastPlayedStation() else { return }
        if let pausedAt = pausedAtTimestamp, Date().timeIntervalSince(pausedAt) > 2.0 {
            playStation(st)
        } else {
            pausedAtTimestamp = nil
            player?.play()
            isPlaying = true
            updateNowPlayingInfo()
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            resumeOrReconnect()
        }
    }

    func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        isLoading = false
        currentStation = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setVolume(_ vol: Float) {
        let clamped = min(max(vol, 0.0), 1.0)
        volume = clamped
        if !isAdPlaying {
            player?.volume = clamped
        }
    }

    func playNext() {
        guard let current = currentStation else { return }
        let blackIds = FavoritesStore.shared.blacklistedIds
        var list = playlist.filter { !blackIds.contains($0.id) }
        if list.count <= 1 {
            let favs = FavoritesStore.shared.favorites.filter { !blackIds.contains($0.id) }
            list = favs.count > 1 ? favs : VRadioDatabase.shared.getPopularStationsByCountryIso(FavoritesStore.shared.detectedCountryIso, limit: 60).filter { !blackIds.contains($0.id) }
            playlist = list
        }
        guard !list.isEmpty else { return }
        let idx = list.firstIndex(where: { $0.id == current.id }) ?? -1
        let nextIdx = idx >= 0 ? (idx + 1) % list.count : 0
        playStation(list[nextIdx], list: list)
    }

    func playPrev() {
        guard let current = currentStation else { return }
        let blackIds = FavoritesStore.shared.blacklistedIds
        var list = playlist.filter { !blackIds.contains($0.id) }
        if list.count <= 1 {
            let favs = FavoritesStore.shared.favorites.filter { !blackIds.contains($0.id) }
            list = favs.count > 1 ? favs : VRadioDatabase.shared.getPopularStationsByCountryIso(FavoritesStore.shared.detectedCountryIso, limit: 60).filter { !blackIds.contains($0.id) }
            playlist = list
        }
        guard !list.isEmpty else { return }
        let idx = list.firstIndex(where: { $0.id == current.id }) ?? 0
        let prevIdx = idx > 0 ? idx - 1 : list.count - 1
        playStation(list[prevIdx], list: list)
    }

    func blacklistCurrentStation() {
        guard let st = currentStation else { return }
        FavoritesStore.shared.addToBlacklist(st)
        playlist = playlist.filter { $0.id != st.id }
        playNext()
    }

    // MARK: - ICY Timed Metadata & Ad Suppression
    func metadataOutput(_ output: AVPlayerItemMetadataOutput, didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup], from track: AVPlayerItemTrack?) {
        for group in groups {
            for item in group.items {
                if let str = item.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    let lower = str.lowercased()
                    if adKeywords.contains(where: { lower.contains($0) }) {
                        isAdPlaying = true
                        player?.volume = 0.0
                    } else {
                        if isAdPlaying {
                            isAdPlaying = false
                            player?.volume = volume
                        }
                        liveTitle = str
                        updateNowPlayingInfo()
                    }
                }
            }
        }
    }

    // MARK: - Lockscreen / AirPlay / CarPlay NowPlaying Metadata
    private func loadArtworkIfNeeded(urlStr: String) {
        guard !urlStr.isEmpty, urlStr != lastArtworkUrl, let url = URL(string: urlStr) else { return }
        lastArtworkUrl = urlStr
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let img = UIImage(data: data) {
                DispatchQueue.main.async {
                    self?.cachedArtworkImage = img
                    self?.updateNowPlayingInfo()
                }
            }
        }.resume()
    }

    private func updateNowPlayingInfo() {
        guard let st = currentStation else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: st.name,
            MPMediaItemPropertyArtist: liveTitle.isEmpty || liveTitle == st.name ? st.subtitleInfo : liveTitle,
            MPMediaItemPropertyAlbumTitle: "AuraRadio HD",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let img = cachedArtworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
