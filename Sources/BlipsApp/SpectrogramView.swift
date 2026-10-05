import AppKit
import BlipsCore
import SwiftUI

/// Pitch over time: time goes right, pitch goes up on a musical scale, and the louder a pitch is,
/// the stronger the color. It's drawn as a small bitmap, one pixel per column and band, scaled up smoothly.
struct SpectrogramView: View {
  let columns: [[Float]]
  let color: Color

  private static let labels: [(String, Double)] = [("100 Hz", 100), ("1 kHz", 1000), ("10 kHz", 10000)]

  var body: some View {
    ZStack {
      if let image = Self.image(columns, color: color) {
        Image(decorative: image, scale: 1)
          .resizable()
          .interpolation(.medium)
      }
      Canvas { context, size in
        for (label, hz) in Self.labels {
          let y = size.height * (1 - log(hz / Spectrogram.lowest) / log(Spectrogram.highest / Spectrogram.lowest))
          context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.5)), with: .color(.primary.opacity(0.12)))
          let text = Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
          if y < size.height / 2 {
            context.draw(text, at: CGPoint(x: size.width - 2, y: y + 2), anchor: .topTrailing)
          } else {
            context.draw(text, at: CGPoint(x: size.width - 2, y: y - 2), anchor: .bottomTrailing)
          }
        }
      }
    }
  }

  static func image(_ columns: [[Float]], color: Color) -> CGImage? {
    guard let bands = columns.first?.count, bands > 0 else { return nil }
    let width = columns.count
    let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .systemPink
    var pixels = [UInt8](repeating: 0, count: width * bands * 4)
    for (x, column) in columns.enumerated() {
      for (band, value) in column.enumerated() {
        let alpha = CGFloat(value * value)
        let index = ((bands - 1 - band) * width + x) * 4
        pixels[index] = UInt8(rgb.redComponent * alpha * 255)
        pixels[index + 1] = UInt8(rgb.greenComponent * alpha * 255)
        pixels[index + 2] = UInt8(rgb.blueComponent * alpha * 255)
        pixels[index + 3] = UInt8(alpha * 255)
      }
    }
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
      width: width, height: bands, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!,
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
    )
  }
}

/// A vertical line that follows the sound while it plays.
struct Playhead: View {
  let progress: Double?

  var body: some View {
    GeometryReader { geometry in
      if let progress {
        Rectangle()
          .fill(Color.primary.opacity(0.6))
          .frame(width: 1.5)
          .offset(x: geometry.size.width * progress - 0.75)
      }
    }
  }
}
