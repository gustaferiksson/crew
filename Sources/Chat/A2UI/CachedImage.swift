import ImageIO
import SwiftUI

nonisolated(unsafe) let cachedImages = {
    let cache = NSCache<NSURL, CGImage>()
    cache.totalCostLimit = 96 * 1024 * 1024
    return cache
}()

@concurrent nonisolated func loadCachedImage(_ url: URL) async throws -> CGImage {
    if let cached = cachedImages.object(forKey: url as NSURL) { return cached }
    let (data, _) = try await URLSession.shared.data(from: url)
    let options = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceThumbnailMaxPixelSize: 1500,
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
        throw URLError(.cannotDecodeContentData)
    }
    cachedImages.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
    return image
}

struct CachedImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (AsyncImagePhase) -> Content

    @State private var phase = AsyncImagePhase.empty
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let cached = cachedImages.object(forKey: url as NSURL).map { AsyncImagePhase.success(Image(decorative: $0, scale: displayScale)) }
        content(cached ?? phase)
            .task(id: url) {
                guard cached == nil else { return }
                do {
                    phase = .success(Image(decorative: try await loadCachedImage(url), scale: displayScale))
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
