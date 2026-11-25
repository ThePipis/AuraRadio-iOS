import Foundation
import AVFoundation
import MediaPlayer
import UIKit
import Combine
import Network

final class RadioPlayerService: NSObject, ObservableObject, AVPlayerItemMetadataOutputPushDelegate {
    static let shared = RadioPlayerService()

    @Published var currentStation: Station?
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = false
    @Published var liveTitle: String = ""
    @Published var isAdPlaying: Bool = false
    @Published var adFilterStatus: String = ""
    @Published var volume: Float = 1.0
    @Published var errorMessage: String?
    @Published var sleepTimerRemainingMinutes: Int = 0

    var playlist: [Station] = []
    private var player: AVPlayer?
    private var playerItemObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var pausedAtTimestamp: Date?
    private var cachedArtworkImage: UIImage?
    private var lastArtworkUrl: String = ""
    private var prerollTimer: Timer?
    private var sleepTimer: Timer?
    private var dataTimer: Timer?
    private var currentPlayToken = UUID()
    private let pathMonitor = NWPathMonitor()
    private var isWifiConnection = true

    private let adKeywords = [
        "ad:", "advertisement", "publicidad", "comercial", "anuncio",
        "adswizz", "triton", "instream", "targetspot", "promo", "sponsor",
        "univision", "ad_", "newenco"
    ]

    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
        detectGeoCountry()
        setupNetworkMonitor()
        startDataUsageTracker()

        if let last = FavoritesStore.shared.getLastPlayedStation(),
           !FavoritesStore.shared.blacklistedIds.contains(last.id) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.playStation(last)
            }
        }
    }

    private func setupNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.isWifiConnection = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
        }
        pathMonitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func startDataUsageTracker() {
        dataTimer?.invalidate()
        dataTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isPlaying, let st = self.currentStation else { return }
            let kbps = max(st.bitrate, 64)
            let bytes5s = Int64((kbps * 1000 / 8) * 5)
            DispatchQueue.main.async {
                FavoritesStore.shared.addDataUsage(bytes: bytes5s, isWifi: self.isWifiConnection)
            }
        }
    }

    func startSleepTimer(minutes: Int) {
        sleepTimer?.invalidate()
        guard minutes > 0 else {
            sleepTimerRemainingMinutes = 0
            return
        }
        sleepTimerRemainingMinutes = minutes
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if self.sleepTimerRemainingMinutes <= 1 {
                timer.invalidate()
                self.sleepTimerRemainingMinutes = 0
                self.stop()
            } else {
                self.sleepTimerRemainingMinutes -= 1
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimer?.invalidate()
        sleepTimer = nil
        sleepTimerRemainingMinutes = 0
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
        let playToken = UUID()
        self.currentPlayToken = playToken

        FavoritesStore.shared.addRecentStation(station.id)
        FavoritesStore.shared.saveLastPlayedStation(station)
        if !station.country.isEmpty {
            FavoritesStore.shared.setLastPlayedCountry(station.country)
        }

        prerollTimer?.invalidate()
        pausedAtTimestamp = nil
        currentStation = station
        isLoading = true
        isPlaying = true
        isAdPlaying = false
        adFilterStatus = ""
        liveTitle = station.name
        errorMessage = nil

        var headers: [String: String] = [
            "User-Agent": station.streamUserAgent.isEmpty ? "VRadio/2.0 (iOS)" : station.streamUserAgent
        ]
        if !station.streamReferer.isEmpty {
            headers["Referer"] = station.streamReferer
        }

        // Si es Mediastream, resolver primero el túnel limpio /live-audio/ sin -aw vía manifest.mpd (0% publicidad)
        if cleanUrlStr.localizedCaseInsensitiveContains("mdstrm.com"),
           let streamId = extractMediastreamId(from: cleanUrlStr) {
            resolveMediastreamCleanHLS(streamId: streamId) { [weak self] resolvedUrl in
                guard let self = self, self.currentPlayToken == playToken else { return }
                let targetUrl = resolvedUrl ?? cleanUrlStr
                let useCustomLoader = (resolvedUrl == nil)
                self.startPlaybackWithResolvedUrl(targetUrl, headers: headers, useCustomHlsLoader: useCustomLoader, station: station)
            }
            return
        }

        let isHls = cleanUrlStr.contains(".m3u8")
        startPlaybackWithResolvedUrl(cleanUrlStr, headers: headers, useCustomHlsLoader: isHls, station: station)
    }

    private func extractMediastreamId(from urlStr: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "([a-f0-9]{24})"),
              let match = regex.firstMatch(in: urlStr, range: NSRange(urlStr.startIndex..., in: urlStr)),
              let range = Range(match.range(at: 1), in: urlStr) else {
            return nil
        }
        return String(urlStr[range])
    }

    private func resolveMediastreamCleanHLS(streamId: String, completion: @escaping (String?) -> Void) {
        guard let mpdUrl = URL(string: "https://mdstrm.com/audio/\(streamId)/manifest.mpd") else {
            completion(nil)
            return
        }
        var req = URLRequest(url: mpdUrl)
        req.timeoutInterval = 3.5
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data = data,
                  let xml = String(data: data, encoding: .utf8),
                  let range = xml.range(of: "<Location>(.*?)</Location>", options: .regularExpression) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let rawTag = String(xml[range])
            let cleanLoc = rawTag
                .replacingOccurrences(of: "<Location>", with: "")
                .replacingOccurrences(of: "</Location>", with: "")
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "manifest.mpd", with: "playlist.m3u8")

            DispatchQueue.main.async {
                completion(cleanLoc.contains("live-audio") ? cleanLoc : nil)
            }
        }.resume()
    }

    private func startPlaybackWithResolvedUrl(_ resolvedUrlStr: String, headers: [String: String], useCustomHlsLoader: Bool, station: Station) {
        var effectiveUrlStr = resolvedUrlStr
        if useCustomHlsLoader {
            if effectiveUrlStr.hasPrefix("https://") {
                effectiveUrlStr = "aurahls://" + effectiveUrlStr.dropFirst("https://".count)
            } else if effectiveUrlStr.hasPrefix("http://") {
                effectiveUrlStr = "aurahlsp://" + effectiveUrlStr.dropFirst("http://".count)
            }
        }

        guard let url = URL(string: effectiveUrlStr) else {
            errorMessage = "URL de emisora inválida"
            isLoading = false
            isPlaying = false
            return
        }

        let isKnownAdStream = resolvedUrlStr.contains("zeno") || resolvedUrlStr.contains("streamtheworld")
        if isKnownAdStream {
            self.isAdPlaying = true
            self.adFilterStatus = "Filtrando anuncio de inicio..."
            prerollTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    if self?.isAdPlaying == true {
                        self?.isAdPlaying = false
                        self?.adFilterStatus = ""
                        self?.player?.volume = self?.volume ?? 1.0
                    }
                }
            }
        }

        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        if useCustomHlsLoader {
            asset.resourceLoader.setDelegate(HLSAdStripperResourceLoader.shared, queue: HLSAdStripperResourceLoader.shared.queue)
        }
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
                        self.isAdPlaying = true
                        self.adFilterStatus = "Anuncio silenciado"
                        self.player?.volume = 0.0
                    } else {
                        if self.isAdPlaying {
                            self.prerollTimer?.invalidate()
                            self.isAdPlaying = false
                            self.adFilterStatus = ""
                            self.player?.volume = self.volume
                        }
                        self.liveTitle = str
                        if let stName = self.currentStation?.name, str != stName {
                            FavoritesStore.shared.addSongHistory(title: str, artist: "", stationName: stName)
                        }
                        self.updateNowPlayingInfo()
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
