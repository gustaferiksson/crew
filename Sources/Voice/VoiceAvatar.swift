#if os(iOS)
import ImageIO
import SwiftUI

struct VoiceAvatar: View {
    let bot: VoiceBot
    let size: CGFloat

    var body: some View {
        AvatarView(shape: .resolve(bot.shape), color: bot.color, expression: .resolve(bot.expression), photo: photo, seed: bot.name, size: size)
    }

    private var photo: Image? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 120] as CFDictionary
        guard let url = VoiceBot.photoDirectory?.appending(path: bot.name),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return Image(decorative: image, scale: 1)
    }
}
#endif
