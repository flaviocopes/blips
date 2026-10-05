#!/usr/bin/env swift
// Renders the Blips icon: an 8-bit waveform made of pixel blocks, mirrored around the middle like a
// real waveform, with an amber sparkle for the blip, baked into a squircle on Apple's macOS icon grid.
// Writes Assets/AppIcon.png, which Scripts/build-app.sh turns into AppIcon.icns.
// Usage: swift Scripts/render-icon.swift

import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
// Apple's macOS icon grid: an 824pt continuous-corner body centered on a 1024pt canvas.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyRadius: CGFloat = 185.4

// The waveform: a column of blocks for each height, loud at the start and fading out, like a blip.
let heights = [3, 7, 9, 5, 7, 3, 1]
let blockSize = CGSize(width: 60, height: 38)
let rowGap: CGFloat = 10
let columnGap: CGFloat = 20
let blockRadius: CGFloat = 12
let waveCenter = CGPoint(x: 494, y: 548)

let sparkleCenter = CGPoint(x: 752, y: 300)
let sparkleRadius: CGFloat = 78

let backgroundTop: UInt32 = 0xFF5C8A
let backgroundBottom: UInt32 = 0x6D28D9
let blockColor: UInt32 = 0xFFFFFF
let accentColor: UInt32 = 0xFFC53D

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
  CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

func squircle(_ rect: CGRect, radius: CGFloat) -> CGPath {
  RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath
}

func drawWaveform(_ context: CGContext) {
  let columnPitch = blockSize.width + columnGap
  let rowPitch = blockSize.height + rowGap
  let width = CGFloat(heights.count) * columnPitch - columnGap
  for (column, height) in heights.enumerated() {
    let x = waveCenter.x - width / 2 + CGFloat(column) * columnPitch
    let top = waveCenter.y - (CGFloat(height) * rowPitch - rowGap) / 2
    for row in 0..<height {
      let rect = CGRect(origin: CGPoint(x: x, y: top + CGFloat(row) * rowPitch), size: blockSize)
      context.addPath(squircle(rect, radius: blockRadius))
    }
  }
  context.setFillColor(rgb(blockColor))
  context.fillPath()
}

// A four-point sparkle with curved sides.
func drawSparkle(_ context: CGContext) {
  let c = sparkleCenter
  let r = sparkleRadius
  let pinch = r * 0.16
  context.move(to: CGPoint(x: c.x, y: c.y - r))
  context.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + pinch, y: c.y - pinch))
  context.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + pinch, y: c.y + pinch))
  context.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - pinch, y: c.y + pinch))
  context.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - pinch, y: c.y - pinch))
  context.setFillColor(rgb(accentColor))
  context.fillPath()
}

// The artwork, in 1024pt canvas coordinates with a top-left origin.
func drawArtwork(_ context: CGContext, scale: CGFloat) {
  // Shadows ignore the transform: the offset is in unflipped pixels, so scale it by hand.
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 30 * scale, color: rgb(0x3B0A6B, 0.4))
  context.beginTransparencyLayer(auxiliaryInfo: nil)
  drawWaveform(context)
  drawSparkle(context)
  context.endTransparencyLayer()
  context.restoreGState()
}

func drawIcon(_ context: CGContext, scale: CGFloat) {
  let bodyPath = squircle(body, radius: bodyRadius)

  // Drop shadow under the body, as in Apple's icon template.
  context.saveGState()
  context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 22 * scale, color: rgb(0x000000, 0.32))
  context.addPath(bodyPath)
  context.setFillColor(rgb(backgroundBottom))
  context.fillPath()
  context.restoreGState()

  context.saveGState()
  context.addPath(bodyPath)
  context.clip()
  context.drawLinearGradient(
    gradient([rgb(backgroundTop), rgb(backgroundBottom)]),
    start: CGPoint(x: 0, y: body.minY),
    end: CGPoint(x: 0, y: body.maxY),
    options: []
  )
  drawArtwork(context, scale: scale)
  context.restoreGState()

  // Hairline highlight along the top edge of the body.
  context.saveGState()
  context.addPath(bodyPath)
  context.setLineWidth(3)
  context.replacePathWithStrokedPath()
  context.clip()
  context.drawLinearGradient(
    gradient([rgb(0xFFFFFF, 0.45), rgb(0xFFFFFF, 0)]),
    start: CGPoint(x: 0, y: body.minY),
    end: CGPoint(x: 0, y: body.midY),
    options: []
  )
  context.restoreGState()
}

func render(pixels: Int) -> CGImage {
  let context = CGContext(
    data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
  )!
  let scale = CGFloat(pixels) / canvas
  context.translateBy(x: 0, y: CGFloat(pixels))
  context.scaleBy(x: scale, y: -scale)
  drawIcon(context, scale: scale)
  return context.makeImage()!
}

func write(_ image: CGImage, to path: String) {
  let url = URL(filePath: path)
  try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
  let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(path)") }
  print("Wrote \(path)")
}

write(render(pixels: 1024), to: "Assets/AppIcon.png")
