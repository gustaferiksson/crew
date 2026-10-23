import ImageIO
import SwiftUI

let cachedImages = {
    let cache = NSCache<NSURL, CGImage>()
    cache.totalCostLimit = 128 * 1024 * 1024
    return cache
}()

// ImageIO's software AV1 decoder blocks on its own workers, so decoding on Swift's cooperative pool deadlocks it on few cores.
nonisolated private let imageDecoding = DispatchQueue(label: "dev.gustaf.crew.image-decoding", qos: .userInitiated)

@concurrent func downloadDownsampledImage(_ url: URL) async throws -> CGImage {
    let (data, _) = try await URLSession.shared.data(from: url)
    return try await withCheckedThrowingContinuation { continuation in
        imageDecoding.async {
            let options = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
            ] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
                return continuation.resume(throwing: URLError(.cannotDecodeContentData))
            }
            continuation.resume(returning: image)
        }
    }
}

struct CachedImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase = AsyncImagePhase.empty
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let cached = cachedImages.object(forKey: url as NSURL)
        content(cached.map { .success(Image(decorative: $0, scale: displayScale)) } ?? phase)
            .task(id: url) {
                if let cached {
                    phase = .success(Image(decorative: cached, scale: displayScale))
                    return
                }
                phase = .empty
                do {
                    let image = try await downloadDownsampledImage(url)
                    cachedImages.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
                    phase = .success(Image(decorative: image, scale: displayScale))
                } catch let failure where !Task.isCancelled {
                    phase = .failure(failure)
                } catch {}
            }
    }
}

struct CardImage: View {
    let url: URL
    let variant: String
    let fit: String

    var body: some View {
        let mode: ContentMode = fit == "contain" || fit == "scaleDown" ? .fit : .fill
        let placeholderHeight: CGFloat = ["icon": 24, "avatar": 40, "smallFeature": 100, "largeFeature": 300][variant] ?? 200
        CachedImage(url: url) { phase in
            if case .success(let image) = phase {
                let image = image.resizable()
                if variant == "icon" {
                    image.aspectRatio(contentMode: mode).frame(width: 24, height: 24).clipped()
                } else if variant == "avatar" {
                    image.aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipShape(.circle)
                } else if variant == "smallFeature" {
                    image.aspectRatio(contentMode: mode).frame(maxWidth: 100, maxHeight: 100).clipped()
                } else if variant == "largeFeature" {
                    image.aspectRatio(contentMode: mode).frame(maxWidth: .infinity).frame(maxHeight: 400).clipped()
                } else if variant == "header" {
                    image.aspectRatio(contentMode: .fill).frame(maxWidth: .infinity).frame(height: 200).clipped()
                } else {
                    image.aspectRatio(contentMode: mode).frame(maxWidth: .infinity).clipped()
                }
            } else if case .failure = phase {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: placeholderHeight)
                    .background(.fill.quaternary)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: placeholderHeight)
            }
        }
    }
}
