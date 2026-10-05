#!/usr/bin/env swift
// Renders the README banner, docs/banner.png, at 2x: the icon, the name, a tagline and
// feature chips on the left, the real window on the right, over square waves.
// The window is docs/screenshot-dark.png, made by Scripts/screenshot.sh.
// Usage: swift Scripts/render-banner.swift

import AppKit
import SwiftUI

let name = "Blips"
let tagline = "8-bit sound effects for your apps,\nmade with jsfxr."
let chips = ["6,000 sounds", "26 categories", "A CLI for agents"]
let size = CGSize(width: 1280, height: 560)
// Where the window's top-left corner sits, and how much it's scaled down.
let windowOrigin = CGPoint(x: 560, y: 62)
let windowScale: CGFloat = 0.54
// Set to 0 for no stars.
let starCount = 0

// The app icon's pink and violet, a bit deeper.
let backgroundTop = Color(hex: 0xB82E66)
let backgroundBottom = Color(hex: 0x34126E)
let glow = Color(hex: 0xFF5C8A)
let muted = Color.white.opacity(0.78)

let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconSource = root.appending(path: "Assets/AppIcon.png")
let screenshot = root.appending(path: "docs/screenshot-dark.png")
let output = root.appending(path: "docs/banner.png")
// scripts/screenshot.sh leaves a 48pt margin around the window for its shadow.
let shadowMargin: CGFloat = 48

extension Color {
  init(hex: UInt32) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

func run(_ tool: String, _ arguments: [String]) -> String {
  let process = Process()
  let pipe = Pipe()
  process.executableURL = URL(filePath: tool)
  process.arguments = arguments
  process.standardOutput = pipe
  try! process.run()
  process.waitUntilExit()
  return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    .trimmingCharacters(in: .whitespacesAndNewlines)
}

// A PNG icon is used as is. It should already have the squircle and its padding.
func renderIcon() -> NSImage {
  guard iconSource.pathExtension == "icon" else { return NSImage(contentsOf: iconSource)! }
  let developer = run("/usr/bin/xcode-select", ["-p"])
  let ictool = URL(filePath: developer).deletingLastPathComponent()
    .appending(path: "Applications/Icon Composer.app/Contents/Executables/ictool").path
  let file = FileManager.default.temporaryDirectory.appending(path: "\(name)-banner-icon.png")
  _ = run(ictool, [
    iconSource.path, "--export-image", "--output-file", file.path, "--platform", "macOS",
    "--rendition", "Default", "--width", "512", "--height", "512", "--scale", "2",
  ])
  return NSImage(contentsOf: file)!
}

/// A square wave, the shape of an 8-bit sound.
func wave(baseline: CGFloat, amplitude: CGFloat, wavelength: CGFloat, phase: CGFloat) -> Path {
  Path { path in
    var x = -wavelength * phase / (2 * .pi)
    var high = true
    path.move(to: CGPoint(x: x, y: baseline - amplitude))
    while x < size.width + wavelength {
      let y = baseline + (high ? -amplitude : amplitude)
      path.addLine(to: CGPoint(x: x + wavelength / 2, y: y))
      path.addLine(to: CGPoint(x: x + wavelength / 2, y: baseline + (high ? amplitude : -amplitude)))
      x += wavelength / 2
      high.toggle()
    }
  }
}

struct Stars: View {
  var body: some View {
    Canvas { context, canvasSize in
      // A fixed seed, so every render puts the stars in the same place.
      var seed: UInt64 = 7
      func random() -> CGFloat {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(seed >> 33) / CGFloat(1 << 31)
      }
      for _ in 0..<starCount {
        let point = CGPoint(x: random() * canvasSize.width, y: random() * canvasSize.height * 0.8)
        let radius = 0.6 + random() * 1.3
        let opacity = 0.15 + random() * 0.45
        context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)), with: .color(.white.opacity(opacity)))
      }
    }
  }
}

struct Banner: View {
  let icon: NSImage
  let window: NSImage

  var body: some View {
    ZStack(alignment: .topLeading) {
      LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
      RadialGradient(colors: [glow.opacity(0.45), glow.opacity(0)], center: UnitPoint(x: 0.16, y: 0.36), startRadius: 0, endRadius: 420)
      Stars()
      ForEach(0..<3) { index in
        wave(baseline: size.height - 92 + CGFloat(index) * 30, amplitude: 8, wavelength: 120 + CGFloat(index) * 40, phase: CGFloat(index) * 1.7)
          .stroke(.white.opacity(0.1 - Double(index) * 0.025), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
      }

      // The screenshot is 2x, so its size in points is half its pixels.
      Image(nsImage: window)
        .resizable()
        .interpolation(.high)
        .frame(width: CGFloat(window.representations[0].pixelsWide) / 2 * windowScale, height: CGFloat(window.representations[0].pixelsHigh) / 2 * windowScale)
        .offset(x: windowOrigin.x - shadowMargin * windowScale, y: windowOrigin.y - shadowMargin * windowScale)

      VStack(alignment: .leading, spacing: 0) {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .frame(width: 132, height: 132)
          .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
        Text(name)
          .font(.system(size: 76, weight: .bold))
          .tracking(-1.8)
          .foregroundStyle(.white)
          .padding(.top, 26)
        Text(tagline)
          .font(.system(size: 27, weight: .regular))
          .lineSpacing(4)
          .foregroundStyle(muted)
          .padding(.top, 8)
        HStack(spacing: 10) {
          ForEach(chips, id: \.self) { chip in
            Text(chip)
              .font(.system(size: 16, weight: .semibold))
              .foregroundStyle(.white.opacity(0.9))
              .padding(.horizontal, 14)
              .padding(.vertical, 7)
              .background(.white.opacity(0.1), in: .capsule)
              .overlay(Capsule().strokeBorder(.white.opacity(0.18)))
          }
        }
        .padding(.top, 26)
      }
      .offset(x: 84, y: 78)
    }
    .frame(width: size.width, height: size.height)
    .clipShape(.rect(cornerRadius: 28))
  }
}

MainActor.assumeIsolated {
  let renderer = ImageRenderer(content: Banner(icon: renderIcon(), window: NSImage(contentsOf: screenshot)!))
  renderer.scale = 2
  // ImageRenderer produces 16 bits per channel. Redraw at 8 bits for a small PNG.
  let image = renderer.cgImage!
  let context = CGContext(
    data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
  try! rep.representation(using: .png, properties: [:])!.write(to: output)
  print("Wrote \(output.path)")
}
