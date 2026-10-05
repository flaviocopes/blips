import AppKit
import BlipsCore
import SwiftUI

/// The app's colors, sizes and shared pieces. The brand colors come from the app icon.
enum Brand {
  static let pink = Color(hex: 0xFF5C8A)
  static let violet = Color(hex: 0x6D28D9)
  static let gradient = LinearGradient(colors: [pink, violet], startPoint: .topLeading, endPoint: .bottomTrailing)
}

enum Surface {
  static let canvas = Color(light: 0xF5F5F8, dark: 0x111116)
  static let raised = Color(light: 0xFFFFFF, dark: 0x1D1D24)
  static let hairline = Color.primary.opacity(0.08)
  static let hover = Color.primary.opacity(0.05)
}

enum Typography {
  static let section = Font.system(size: 10, weight: .semibold)
  static let caption = Font.system(size: 11)
  static let mono = Font.system(size: 11, design: .monospaced)
  static let body = Font.system(size: 13)
  static let bodyStrong = Font.system(size: 13, weight: .medium)
  static let tile = Font.system(size: 12, weight: .semibold)
  static let title = Font.system(size: 17, weight: .semibold, design: .rounded)
}

/// The color and symbol of each category, used on its waveforms, badges and sidebar row.
struct CategoryStyle {
  let color: Color
  let symbol: String

  init(_ category: String) {
    switch category {
    case "click": (color, symbol) = (Color(hex: 0x94A3B8), "cursorarrow.click")
    case "blip": (color, symbol) = (Color(hex: 0x22D3EE), "dot.radiowaves.right")
    case "pop": (color, symbol) = (Color(hex: 0xF472B6), "bubble.left.fill")
    case "toggle": (color, symbol) = (Color(hex: 0xA78BFA), "switch.2")
    case "success": (color, symbol) = (Color(hex: 0x34D399), "checkmark.circle.fill")
    case "error": (color, symbol) = (Color(hex: 0xF87171), "xmark.octagon.fill")
    case "notification": (color, symbol) = (Color(hex: 0xFBBF24), "bell.fill")
    case "swoosh": (color, symbol) = (Color(hex: 0x60A5FA), "wind")
    case "coin": (color, symbol) = (Color(hex: 0xFACC15), "dollarsign.circle.fill")
    case "powerup": (color, symbol) = (Color(hex: 0xC084FC), "bolt.fill")
    case "jump": (color, symbol) = (Color(hex: 0x4ADE80), "hare.fill")
    case "laser": (color, symbol) = (Color(hex: 0xFB7185), "rays")
    case "explosion": (color, symbol) = (Color(hex: 0xFB923C), "burst.fill")
    case "hit": (color, symbol) = (Color(hex: 0xE879F9), "hammer.fill")
    case "sent": (color, symbol) = (Color(hex: 0x38BDF8), "paperplane.fill")
    case "received": (color, symbol) = (Color(hex: 0x2DD4BF), "tray.and.arrow.down.fill")
    case "trash": (color, symbol) = (Color(hex: 0xA8A29E), "trash.fill")
    case "confirm": (color, symbol) = (Color(hex: 0x10B981), "checkmark.seal.fill")
    case "reward": (color, symbol) = (Color(hex: 0xF59E0B), "trophy.fill")
    case "impact": (color, symbol) = (Color(hex: 0xDC2626), "bolt.horizontal.fill")
    case "zap": (color, symbol) = (Color(hex: 0xE11D48), "scope")
    case "fanfare": (color, symbol) = (Color(hex: 0xF97316), "party.popper.fill")
    case "gameover": (color, symbol) = (Color(hex: 0x6B7280), "gamecontroller.fill")
    case "countdown": (color, symbol) = (Color(hex: 0x3B82F6), "timer")
    case "startup": (color, symbol) = (Color(hex: 0x8B5CF6), "power")
    case "alarm": (color, symbol) = (Color(hex: 0xEF4444), "alarm.fill")
    default: (color, symbol) = (Brand.pink, "waveform")
    }
  }
}

/// A category's symbol on a rounded square of its color.
struct CategoryIcon: View {
  let category: String
  var size: CGFloat = 20

  var body: some View {
    let style = CategoryStyle(category)
    Image(systemName: style.symbol)
      .font(.system(size: size * 0.52, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: size, height: size)
      .background(style.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
  }
}

/// A small rounded label, for tags.
struct Chip: View {
  let text: String

  var body: some View {
    Text(text)
      .font(Typography.caption)
      .padding(.horizontal, 8)
      .padding(.vertical, 3)
      .background(Surface.hover, in: Capsule())
      .overlay(Capsule().strokeBorder(Surface.hairline))
  }
}

/// An uppercase label above a group, like "PARAMETERS".
struct SectionLabel: View {
  let text: String

  var body: some View {
    Text(text.uppercased())
      .font(Typography.section)
      .tracking(0.8)
      .foregroundStyle(.secondary)
  }
}

struct EmptyState<Actions: View>: View {
  let symbol: String
  let title: String
  let message: String
  @ViewBuilder var actions: Actions

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.white)
        .frame(width: 52, height: 52)
        .background(Brand.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Brand.violet.opacity(0.3), radius: 10, y: 4)
      Text(title)
        .font(Typography.title)
      Text(message)
        .font(Typography.body)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 300)
      actions
        .padding(.top, 4)
    }
    .padding(24)
  }
}

/// The gradient Play button.
struct GradientButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    GradientBody(configuration: configuration)
  }

  private struct GradientBody: View {
    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      configuration.label
        .font(Typography.bodyStrong)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(Brand.gradient, in: Capsule())
        .shadow(color: Brand.violet.opacity(configuration.isPressed || !isEnabled ? 0.1 : 0.35), radius: 8, y: 3)
        .opacity(isEnabled ? 1 : 0.4)
        .scaleEffect(configuration.isPressed ? 0.97 : 1)
        .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
  }
}

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  init(light: UInt32, dark: UInt32) {
    self.init(
      nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(
          srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
          green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255,
          alpha: 1
        )
      }
    )
  }
}

extension Sound {
  var formattedDuration: String {
    duration < 1 ? "\(Int((duration * 1000).rounded())) ms" : String(format: "%.2f s", duration)
  }
}
