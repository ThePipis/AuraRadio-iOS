import Foundation
import Network

/// Proxy HTTP local (127.0.0.1) equivalente exacto a AdStrippingInterceptor (OkHttp) en Android.
/// Intercepta playlists HLS (.m3u8), resuelve rutas relativas y purga quirúrgicamente todas
/// las cuñas publicitarias SSAI (AdsWizz, Univision, Triton, newEnco) antes de entregarlas a AVPlayer.
final class LocalAdStrippingProxy {
    static let shared = LocalAdStrippingProxy()

    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private let queue = DispatchQueue(label: "com.auraradio.localproxy", qos: .userInitiated)
    private let readyLock = DispatchSemaphore(value: 0)
    private var isReadySignaled = false

    private let adMarkers = [
        "adswizzcontext", "x-ad-id", "x-ad-duration", "x-ad-creative",
        "univision", "/segment/", "/ad_", "ad_", "newenco", "preroll", "ad_break", "triton"
    ]

    private init() {
        start()
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: .any)
            self.listener = newListener

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let assignedPort = newListener.port?.rawValue {
                        self.port = assignedPort
                        print("[LocalAdStrippingProxy] Listening on 127.0.0.1:\(assignedPort)")
                    }
                    if !self.isReadySignaled {
                        self.isReadySignaled = true
                        self.readyLock.signal()
                    }
                case .failed(let error):
                    print("[LocalAdStrippingProxy] Failed: \(error)")
                    self.listener = nil
                    if !self.isReadySignaled {
                        self.isReadySignaled = true
                        self.readyLock.signal()
                    }
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }

            newListener.start(queue: queue)
        } catch {
            print("[LocalAdStrippingProxy] Init error: \(error)")
        }
    }

    func proxiedUrlIfNeeded(for urlStr: String) -> String {
        if port == 0 {
            _ = readyLock.wait(timeout: .now() + 1.0)
        }
        guard port > 0,
              let data = urlStr.data(using: .utf8) else {
            return urlStr
        }
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "http://127.0.0.1:\(port)/m3u8?b=\(b64)"
    }

    private func decodeBase64Url(_ str: String) -> String? {
        var b64 = str
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = b64.count % 4
        if remainder > 0 {
            b64 += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, error in
            guard let self = self, let data = data, error == nil,
                  let reqStr = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let firstLine = reqStr.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            guard parts.count >= 2 else {
                self.sendError(connection, code: 400, message: "Bad Request")
                return
            }

            let path = String(parts[1])
            guard let comps = URLComponents(string: "http://127.0.0.1" + path),
                  let bParam = comps.queryItems?.first(where: { $0.name == "b" })?.value,
                  let targetUrlStr = self.decodeBase64Url(bParam),
                  let targetUrl = URL(string: targetUrlStr) else {
                self.sendError(connection, code: 400, message: "Missing URL")
                return
            }

            var req = URLRequest(url: targetUrl)
            req.timeoutInterval = 8.0
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

            URLSession.shared.dataTask(with: req) { respData, response, err in
                guard let respData = respData, err == nil else {
                    self.sendError(connection, code: 502, message: "Upstream Error")
                    return
                }

                let finalUrl = response?.url ?? targetUrl
                if let text = String(data: respData, encoding: .utf8), text.contains("#EXTM3U") {
                    let cleaned = self.purgeAdsFromM3u8(text, baseUrl: finalUrl)
                    let bodyData = cleaned.data(using: .utf8) ?? respData
                    self.sendResponse(connection, contentType: "application/vnd.apple.mpegurl", body: bodyData)
                } else {
                    let mime = (response as? HTTPURLResponse)?.mimeType ?? "application/octet-stream"
                    self.sendResponse(connection, contentType: mime, body: respData)
                }
            }.resume()
        }
    }

    private func sendResponse(_ connection: NWConnection, contentType: String, body: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var fullData = header.data(using: .utf8) ?? Data()
        fullData.append(body)
        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func sendError(_ connection: NWConnection, code: Int, message: String) {
        let body = message.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(code) \(message)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var fullData = header.data(using: .utf8) ?? Data()
        fullData.append(body)
        connection.send(content: fullData, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func isAdMarker(_ line: String) -> Bool {
        let lower = line.lowercased()
        return adMarkers.contains { lower.contains($0) }
    }

    private func resolveAbsoluteUrl(_ urlLine: String, baseUrl: URL) -> String {
        if urlLine.hasPrefix("http://") || urlLine.hasPrefix("https://") {
            return urlLine
        }
        return URL(string: urlLine, relativeTo: baseUrl)?.absoluteString ?? urlLine
    }

    func purgeAdsFromM3u8(_ m3u8: String, baseUrl: URL) -> String {
        let lines = m3u8.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var cleaned: [String] = []
        var pendingTags: [String] = []
        var hasMedia = false

        for line in lines {
            if line.hasPrefix("#EXTM3U") ||
               line.hasPrefix("#EXT-X-VERSION") ||
               line.hasPrefix("#EXT-X-TARGETDURATION") ||
               line.hasPrefix("#EXT-X-MEDIA-SEQUENCE") ||
               line.hasPrefix("#EXT-X-DISCONTINUITY-SEQUENCE") ||
               line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") {
                if !isAdMarker(line) {
                    cleaned.append(line)
                }
                continue
            }

            if line.hasPrefix("#") {
                if line == "#EXT-X-DISCONTINUITY" || isAdMarker(line) {
                    continue
                }
                pendingTags.append(line)
                continue
            }

            // Es una URL de media o sub-playlist
            if isAdMarker(line) {
                pendingTags.removeAll()
                continue
            }

            let absUrl = resolveAbsoluteUrl(line, baseUrl: baseUrl)
            let isSubPlaylist = absUrl.lowercased().contains(".m3u8")
            let outputUrl = isSubPlaylist ? proxiedUrlIfNeeded(for: absUrl) : absUrl

            cleaned.append(contentsOf: pendingTags)
            cleaned.append(outputUrl)
            pendingTags.removeAll()
            hasMedia = true
        }

        if !hasMedia {
            // Guardia anti-congelamiento si el servidor envió 100% cuñas en este snapshot
            return m3u8
        }
        return cleaned.joined(separator: "\n")
    }
}
