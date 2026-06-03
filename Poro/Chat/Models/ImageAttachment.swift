import AppKit
import Foundation

/// Converts a picked/dropped `NSImage` into a `ChatImage`, downscaling and JPEG-encoding so the
/// base64 payload stays small (vision models tile large images, wasting tokens and free-tier quota).
enum ImageAttachment {
  /// Decodes image bytes, then downscales + JPEG-encodes. Safe to call off the main actor.
  static func make(
    from data: Data,
    maxDimension: CGFloat = 1024,
    quality: CGFloat = 0.7
  ) -> ChatImage? {
    guard let image = NSImage(data: data) else { return nil }
    return make(from: image, maxDimension: maxDimension, quality: quality)
  }

  static func make(
    from image: NSImage,
    maxDimension: CGFloat = 1024,
    quality: CGFloat = 0.7
  ) -> ChatImage? {
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return nil
    }

    let pixelWidth = CGFloat(cgImage.width)
    let pixelHeight = CGFloat(cgImage.height)
    guard pixelWidth > 0, pixelHeight > 0 else { return nil }

    let longestEdge = max(pixelWidth, pixelHeight)
    let scale: CGFloat = if longestEdge > maxDimension { maxDimension / longestEdge } else { 1 }
    let targetWidth = Int((pixelWidth * scale).rounded())
    let targetHeight = Int((pixelHeight * scale).rounded())

    guard
      let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetWidth,
        pixelsHigh: targetHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    else {
      return nil
    }
    bitmap.size = NSSize(width: targetWidth, height: targetHeight)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
      in: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
      from: .zero,
      operation: .copy,
      fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard
      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    else {
      return nil
    }

    return ChatImage(data: jpeg, mimeType: "image/jpeg")
  }
}
