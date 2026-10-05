import BlipsCore
import SwiftUI

/// The selected sound: a large waveform to play it, what it's like, how to use it, and the jsfxr
/// parameters it was made from, drawn as the sliders of jsfxr's editor.
struct SoundInspector: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    if let sound = model.selectedSound {
      ScrollView {
        SoundDetails(sound: sound)
          .padding(20)
      }
    } else {
      EmptyState(symbol: "hand.tap", title: "Pick a sound", message: "Click a sound to hear it. The arrow keys play the next one.") {
        EmptyView()
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }
}

struct SoundDetails: View {
  @Environment(AppModel.self) private var model
  let sound: Sound

  var body: some View {
    let style = CategoryStyle(sound.category)
    let category = model.library?.category(sound.category)
    let isPlaying = model.playingID == sound.id

    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 8) {
          CategoryIcon(category: sound.category, size: 18)
          Text(category?.name ?? sound.category)
            .font(Typography.bodyStrong)
            .foregroundStyle(.secondary)
        }
        Text(sound.name)
          .font(Typography.title)
        HStack(spacing: 6) {
          Text(sound.id)
            .font(Typography.mono)
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
          Button {
            model.copy(sound.id)
          } label: {
            Image(systemName: "doc.on.doc")
              .font(.system(size: 10))
          }
          .buttonStyle(.borderless)
          .help("Copy the ID")
        }
      }

      Group {
        if isPlaying {
          TimelineView(.animation) { _ in
            WaveformView(peaks: model.peaks(of: sound), color: style.color, progress: model.progress(of: sound.id), barWidth: 3, gap: 2)
          }
        } else {
          WaveformView(peaks: model.peaks(of: sound), color: style.color, barWidth: 3, gap: 2)
        }
      }
      .frame(height: 96)
      .padding(14)
      .background(Surface.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.hairline))
      .contentShape(Rectangle())
      .onTapGesture { model.select(sound) }
      .onDrag { NSItemProvider(contentsOf: model.url(for: sound)) ?? NSItemProvider() }

      HStack {
        Button {
          isPlaying ? model.stop() : model.select(sound)
        } label: {
          Label(isPlaying ? "Stop" : "Play", systemImage: isPlaying ? "stop.fill" : "play.fill")
        }
        .buttonStyle(GradientButtonStyle())
        Spacer()
        Text(sound.formattedDuration)
          .font(Typography.bodyStrong)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }

      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "Pitch over time")
        SpectrogramView(columns: model.spectrogram(of: sound), color: style.color)
          .overlay {
            if isPlaying {
              TimelineView(.animation) { _ in
                Playhead(progress: model.progress(of: sound.id))
              }
            }
          }
          .frame(height: 110)
        .padding(10)
        .background(Surface.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.hairline))
      }

      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "Sounds like")
        FlowLayout(spacing: 6) {
          ForEach(sound.tags, id: \.self) { Chip(text: $0) }
        }
        if let params = sound.params {
          Text("Starts at \(Int(params.startFrequency.rounded())) Hz, on a \(params.wave.name) wave.")
            .font(Typography.caption)
            .foregroundStyle(.secondary)
        }
      }

      if let parts = sound.parts {
        PartsSection(parts: parts, duration: sound.duration, color: style.color)
      }

      VStack(alignment: .leading, spacing: 8) {
        SectionLabel(text: "Use it")
        HStack(spacing: 8) {
          Button("Export…") { model.export(sound) }
          Button("Copy File") { model.copyFile(sound) }
          Button("Show in Finder") { model.revealInFinder(sound) }
        }
        .controlSize(.small)
        CommandBox(command: model.exportCommand(for: sound))
        if sound.sfxrURL != nil {
          Button {
            model.openInSfxr(sound)
          } label: {
            Label("Edit a copy in sfxr.me", systemImage: "arrow.up.right.square")
              .font(Typography.caption)
          }
          .buttonStyle(.link)
        }
      }

      if let params = sound.params {
        VStack(alignment: .leading, spacing: 8) {
          SectionLabel(text: "jsfxr parameters")
          ParameterList(params: params, color: style.color)
        }
      }
    }
  }
}

/// What a combo is made of, as a timeline of its parts you can click to hear on their own,
/// or the notes of a jingle, as a piano roll.
struct PartsSection: View {
  @Environment(AppModel.self) private var model
  let parts: [Part]
  let duration: Double
  let color: Color

  private var isCombo: Bool { parts.contains { $0.sound != nil } }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SectionLabel(text: isCombo ? "Made of" : "\(parts.count) notes")
      Group {
        if isCombo {
          ComboTimeline(parts: parts, duration: duration)
            .frame(height: CGFloat(parts.count) * 26 - 6)
        } else {
          PianoRoll(parts: parts, duration: duration, color: color)
            .frame(height: 84)
        }
      }
      .padding(10)
      .background(Surface.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Surface.hairline))

      if isCombo {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
          if let id = part.sound {
            Button {
              model.show(id)
            } label: {
              HStack(spacing: 8) {
                CategoryIcon(category: model.sound(id)?.category ?? Self.category(of: id), size: 18)
                VStack(alignment: .leading, spacing: 1) {
                  Text(model.sound(id)?.name ?? id)
                    .font(Typography.bodyStrong)
                  Text(id)
                    .font(Typography.mono)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(format: "at %.2f s", part.start))
                  .font(Typography.caption)
                  .monospacedDigit()
                  .foregroundStyle(.secondary)
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(model.sound(id) == nil)
            .help(model.sound(id) == nil ? "\(id) isn't in this library" : "Play \(id) on its own")
          }
        }
      } else {
        Text(parts.filter { $0.volume == 1 }.map(\.params.noteName).joined(separator: " "))
          .font(Typography.mono)
          .foregroundStyle(.secondary)
      }
    }
  }

  /// `swoosh-042` comes from the swoosh category.
  static func category(of id: String) -> String {
    id.split(separator: "-").dropLast().joined(separator: "-")
  }
}

/// Each part of a combo on its own row, from when it starts to when it ends.
struct ComboTimeline: View {
  let parts: [Part]
  let duration: Double

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      ForEach(Array(parts.enumerated()), id: \.offset) { row, part in
        let id = part.sound ?? ""
        let start = width * part.start / duration
        let length = max(width * min(part.duration, duration - part.start) / duration, 6)
        Text(id)
          .font(.system(size: 10, weight: .semibold, design: .monospaced))
          .foregroundStyle(.white)
          .lineLimit(1)
          .padding(.horizontal, 6)
          .frame(width: length, height: 20, alignment: .leading)
          .background(CategoryStyle(PartsSection.category(of: id)).color.gradient, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
          .offset(x: start, y: CGFloat(row) * 26)
      }
    }
  }
}

/// The notes of a jingle: time goes right, pitch goes up, and the second voice is fainter.
struct PianoRoll: View {
  let parts: [Part]
  let duration: Double
  let color: Color

  var body: some View {
    Canvas { context, size in
      let pitches = parts.map { log2($0.params.startFrequency) }
      guard let lowest = pitches.min(), let highest = pitches.max() else { return }
      let range = max(highest - lowest, 1)
      let barHeight: CGFloat = 7
      for (part, pitch) in zip(parts, pitches) {
        let x = size.width * part.start / duration
        let width = max(size.width * part.params.heldLength / duration, 4)
        let y = (size.height - barHeight) * (1 - (pitch - lowest) / range)
        let bar = Path(roundedRect: CGRect(x: x, y: y, width: width, height: barHeight), cornerRadius: barHeight / 2)
        context.fill(bar, with: .color(color.opacity(part.volume < 1 ? 0.4 : 1)))
      }
    }
  }
}

/// A shell command in a box, with a button that copies it.
struct CommandBox: View {
  @Environment(AppModel.self) private var model
  let command: String

  var body: some View {
    HStack(spacing: 8) {
      Text(command)
        .font(Typography.mono)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
      Spacer(minLength: 0)
      Button {
        model.copy(command)
      } label: {
        Image(systemName: "doc.on.doc")
          .font(.system(size: 10))
      }
      .buttonStyle(.borderless)
      .help("Copy the command")
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(Surface.hover, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
  }
}

/// jsfxr's sliders, in the order and with the names of its editor. Signed ones fill from the middle.
struct ParameterList: View {
  let params: SoundParams
  let color: Color

  private static let rows: [(String, KeyPath<SoundParams, Double>, Bool)] = [
    ("Attack", \.attack, false),
    ("Sustain", \.sustain, false),
    ("Punch", \.punch, false),
    ("Decay", \.decay, false),
    ("Frequency", \.baseFrequency, false),
    ("Min frequency", \.frequencyLimit, false),
    ("Slide", \.frequencySlide, true),
    ("Delta slide", \.frequencyDeltaSlide, true),
    ("Vibrato depth", \.vibratoDepth, false),
    ("Vibrato speed", \.vibratoSpeed, false),
    ("Change amount", \.arpeggioChange, true),
    ("Change speed", \.arpeggioSpeed, false),
    ("Square duty", \.duty, false),
    ("Duty sweep", \.dutySweep, true),
    ("Repeat speed", \.repeatSpeed, false),
    ("Phaser offset", \.flangerOffset, true),
    ("Phaser sweep", \.flangerSweep, true),
    ("LP cutoff", \.lowPassCutoff, false),
    ("LP sweep", \.lowPassSweep, true),
    ("LP resonance", \.lowPassResonance, false),
    ("HP cutoff", \.highPassCutoff, false),
    ("HP sweep", \.highPassSweep, true),
  ]

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
      ForEach(Self.rows, id: \.0) { name, keyPath, signed in
        let value = params[keyPath: keyPath]
        GridRow {
          Text(name)
            .font(Typography.caption)
            .foregroundStyle(.secondary)
          Slider(value: value, signed: signed, color: color)
            .frame(height: 6)
          Text(String(format: "%.2f", value))
            .font(Typography.mono)
            .foregroundStyle(value == 0 ? .tertiary : .secondary)
            .gridColumnAlignment(.trailing)
        }
      }
    }
  }

  private struct Slider: View {
    let value: Double
    let signed: Bool
    let color: Color

    var body: some View {
      GeometryReader { geometry in
        let width = geometry.size.width
        let clamped = CGFloat(min(max(value, signed ? -1 : 0), 1))
        let start: CGFloat = signed ? width / 2 + min(0, clamped) * width / 2 : 0
        let length: CGFloat = signed ? abs(clamped) * width / 2 : clamped * width
        ZStack(alignment: .leading) {
          Capsule().fill(Surface.hover)
          Capsule().fill(color).frame(width: max(length, value == 0 ? 0 : 2)).offset(x: start)
          if signed {
            Rectangle().fill(Color.primary.opacity(0.2)).frame(width: 1).offset(x: width / 2)
          }
        }
      }
    }
  }
}

/// Lays out its children in rows, wrapping to a new row when one is full.
struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
    let rows = arrange(subviews, width: proposal.width ?? .infinity)
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    let width = rows.map(\.width).max() ?? 0
    return CGSize(width: proposal.width ?? width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
    var y = bounds.minY
    for row in arrange(subviews, width: bounds.width) {
      var x = bounds.minX
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
    var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
    var current: (indices: [Int], width: CGFloat, height: CGFloat) = ([], 0, 0)
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
      if needed > width, !current.indices.isEmpty {
        rows.append(current)
        current = ([index], size.width, size.height)
      } else {
        current = (current.indices + [index], needed, max(current.height, size.height))
      }
    }
    if !current.indices.isEmpty { rows.append(current) }
    return rows
  }
}
