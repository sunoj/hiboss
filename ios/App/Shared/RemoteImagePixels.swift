// Pixel-size buckets for downsampled remote images and their SwiftUI Image form.
// Exports RemoteImagePixels; buckets only grow so a resize never refetches a smaller copy.
// Dependencies: SwiftUI, UIKit and HibossKit DecodedImage.

import HibossKit
import SwiftUI
import UIKit

enum RemoteImagePixels {
    private static let buckets = [512, 768, 1024, 1536, 2048, 3072, 4096]

    /// The smallest bucket covering 1.5 x the frame's longest side, enough for a 3:2 fill crop.
    static func bucket(for size: CGSize, scale: CGFloat) -> Int {
        let needed = Int((max(size.width, size.height) * max(scale, 1) * 1.5).rounded(.up))
        return buckets.first { $0 >= needed } ?? buckets[buckets.count - 1]
    }

    /// Keeps the original's point size, as AsyncImage did, so layouts that size to the image do not change.
    static func image(_ decoded: DecodedImage) -> Image {
        Image(uiImage: UIImage(cgImage: decoded.cgImage, scale: decoded.scale, orientation: .up))
    }
}
