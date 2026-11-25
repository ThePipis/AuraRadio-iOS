import Foundation
import AVFoundation

final class HLSAdStripperResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    static let shared = HLSAdStripperResourceLoader()
    let queue = DispatchQueue(label: "com.auraradio.hlsloader", qos: .userInitiated)

    private let adMarkers = [
        "univision", "adswizz", "x-ad-id", "x-ad-duration", "x-ad-creative",
        "/segment/", "/ad_", "ad_", "newenco", "preroll", "ad_break", "triton"
    ]

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        guard let customUrl = loadingRequest.request.url else { return false }

        var realUrlStr = customUrl.absoluteString
        if realUrlStr.hasPrefix("aurahls://") {
            realUrlStr = "https://" + realUrlStr.dropFirst("aurahls://".count)
        } else if realUrlStr.hasPrefix("aurahlsp://") {
            realUrlStr = "http://" + realUrlStr.dropFirst("aurahlsp://".count)
        } else {
            return false
        }

        guard let realUrl = URL(string: realUrlStr) else { return false }

        var request = URLRequest(url: realUrl)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else {
                loadingRequest.finishLoading(with: error)
                return
            }

            if let text = String(data: data, encoding: .utf8), text.contains("#EXTM3U") {
                let cleaned = self.purgeM3u8(text)
                if let cleanData = cleaned.data(using: .utf8) {
                    loadingRequest.contentInformationRequest?.contentType = "application/x-mpegURL"
                    loadingRequest.contentInformationRequest?.isByteRangeAccessSupported = false
                    loadingRequest.contentInformationRequest?.contentLength = Int64(cleanData.count)
                    loadingRequest.dataRequest?.respond(with: cleanData)
                    loadingRequest.finishLoading()
                    return
                }
            }

            if let httpResp = response as? HTTPURLResponse {
                loadingRequest.contentInformationRequest?.contentType = httpResp.mimeType ?? "video/mp2t"
                loadingRequest.contentInformationRequest?.contentLength = httpResp.expectedContentLength
            }
            loadingRequest.dataRequest?.respond(with: data)
            loadingRequest.finishLoading()
        }
        task.resume()
        return true
    }

    private func isAdLine(_ line: String) -> Bool {
        let lower = line.lowercased()
        return adMarkers.contains { lower.contains($0) }
    }

    func purgeM3u8(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var header: [String] = []
        var items: [([String], String)] = []
        var currentTags: [String] = []

        for line in lines {
            if line.hasPrefix("#EXTM3U") ||
               line.hasPrefix("#EXT-X-VERSION") ||
               line.hasPrefix("#EXT-X-TARGETDURATION") ||
               line.hasPrefix("#EXT-X-MEDIA-SEQUENCE") ||
               line.hasPrefix("#EXT-X-PROGRAM-DATE-TIME") {
                header.append(line)
            } else if line.hasPrefix("#EXTINF") || line.hasPrefix("#EXT-X-") {
                if !isAdLine(line) && line != "#EXT-X-DISCONTINUITY" {
                    currentTags.append(line)
                }
            } else if !line.hasPrefix("#") {
                if !isAdLine(line) {
                    var finalUrl = line
                    if finalUrl.contains(".m3u8") {
                        if finalUrl.hasPrefix("https://") {
                            finalUrl = "aurahls://" + finalUrl.dropFirst("https://".count)
                        } else if finalUrl.hasPrefix("http://") {
                            finalUrl = "aurahlsp://" + finalUrl.dropFirst("http://".count)
                        }
                    }
                    items.append((currentTags, finalUrl))
                }
                currentTags = []
            }
        }

        var result = header
        for (tags, url) in items {
            result.append(contentsOf: tags)
            result.append(url)
        }
        return result.joined(separator: "\n")
    }
}
