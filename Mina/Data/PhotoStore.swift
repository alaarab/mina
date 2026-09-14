import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Turns a picked or captured picture into what the log stores: a full-size
/// JPEG small enough to sync (at most 1600 px on the long side) and a thumbnail
/// for rows. Both are rendered into a fresh bitmap and written by ImageIO from
/// that bare image, so nothing the camera embedded (GPS, capture time, lens,
/// device) survives: the log syncs to the partner's phone and must never carry
/// where a photo was taken.
///
/// Pure functions on values; nothing here touches Core Data or the UI.
enum PhotoStore {
    static let fullMaxSide: CGFloat = 1600
    static let fullQuality: CGFloat = 0.8
    static let thumbMaxSide: CGFloat = 200
    /// The thumbnail is inline in every row, so it has a hard ceiling.
    static let thumbMaxBytes = 16 * 1024

    /// The full picture and the thumbnail, or nil when the bytes are not an image.
    static func prepare(data: Data) -> EntryPhoto? {
        guard let image = UIImage(data: data) else { return nil }
        return prepare(image)
    }

    static func prepare(_ image: UIImage) -> EntryPhoto? {
        let full = downscaled(image, maxSide: fullMaxSide)
        let thumbImage = downscaled(image, maxSide: thumbMaxSide)
        guard let fullData = jpeg(full, quality: fullQuality) else { return nil }
        var thumbData: Data?
        for quality in stride(from: 0.7, through: 0.2, by: -0.1) {
            guard let candidate = jpeg(thumbImage, quality: quality) else { break }
            thumbData = candidate
            if candidate.count <= thumbMaxBytes { break }
        }
        guard let thumbData else { return nil }
        return EntryPhoto(full: fullData, thumb: thumbData)
    }

    /// Renders into a new bitmap no larger than `maxSide` on its long edge,
    /// baking in the orientation. An image already small enough is still
    /// re-rendered, which is what drops its metadata.
    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(.down), height: (size.height * scale).rounded(.down))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        // Standard range, 8 bits a channel: on a wide-gamut device the default
        // is a 16-bit extended-range bitmap, which the JPEG encoder cannot
        // take and silently writes as a 20-byte stub.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: target, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Encodes the bare bitmap. Only the pixel size and colour space go in the
    /// file; the GPS, Exif and TIFF blocks of the original are not carried
    /// because `image` no longer has them.
    static func jpeg(_ image: UIImage, quality: CGFloat) -> Data? {
        guard let cgImage = image.cgImage else { return nil }
        return jpeg(cgImage, quality: quality)
    }

    static func jpeg(_ cgImage: CGImage, quality: CGFloat) -> Data? {
        guard let cgImage = eightBitSRGB(cgImage) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // Only the quality goes in. A bare CGImage carries no metadata, so
        // there is nothing to remove; the source file's blocks were left
        // behind when it was decoded.
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        // A JPEG with only its header is what a failed encode looks like.
        guard CGImageDestinationFinalize(destination), output.length > 64 else { return nil }
        return output as Data
    }

    /// The same pixels as an 8-bit sRGB bitmap, which is what JPEG holds.
    /// Anything already in that shape is returned as is.
    private static func eightBitSRGB(_ cgImage: CGImage) -> CGImage? {
        let isPlain = cgImage.bitsPerComponent == 8 && cgImage.bitmapInfo.contains(.floatComponents) == false
            && cgImage.colorSpace?.model == .rgb
        if isPlain { return cgImage }
        guard let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        return context.makeImage()
    }

    /// Re-encodes an existing JPEG (or any image file) without its metadata,
    /// keeping the pixels as they are. `prepare` already does this as part of
    /// the resize; this is for bytes that are the right size already.
    static func strippingMetadata(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return jpeg(cgImage, quality: fullQuality)
    }

    /// The pixel size of an encoded image, for tests and size notes.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight as String] as? NSNumber else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }

    /// Every metadata dictionary ImageIO finds in the file, keyed by block name
    /// ("{GPS}", "{Exif}", "{TIFF}"...). Empty for a clean file.
    static func metadata(of data: Data) -> [String: [String: Any]] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return [:] }
        var blocks: [String: [String: Any]] = [:]
        for (key, value) in properties {
            if let dictionary = value as? [String: Any] { blocks[key] = dictionary }
        }
        return blocks
    }
}
