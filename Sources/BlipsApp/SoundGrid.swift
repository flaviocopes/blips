import BlipsCore
import SwiftUI

/// The sounds as tiles with their waveforms, under a header for each category.
/// A click plays a sound, the arrow keys move and play, Space plays or stops,
/// ⌘C copies the file, and a tile drags out as its WAV file.
struct SoundGrid: View {
  @Environment(AppModel.self) private var model
  @FocusState private var focused: Bool
  @State private var columns = 1

  static let tileWidth: CGFloat = 200
  static let spacing: CGFloat = 12
  static let padding: CGFloat = 20

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: Self.tileWidth), spacing: Self.spacing)],
          alignment: .leading,
          spacing: Self.spacing,
          pinnedViews: [.sectionHeaders]
        ) {
          ForEach(model.sections, id: \.category.id) { section in
            Section {
              ForEach(section.sounds) { sound in
                SoundTile(sound: sound)
                  .id(sound.id)
              }
            } header: {
              SectionHeader(category: section.category, count: section.sounds.count)
            }
          }
        }
        .padding(.horizontal, Self.padding)
        .padding(.bottom, Self.padding)
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
        columns = max(1, Int((width - 2 * Self.padding + Self.spacing) / (Self.tileWidth + Self.spacing)))
      }
      .focusable()
      .focused($focused)
      .focusEffectDisabled()
      .onKeyPress(.leftArrow) { handled { model.move(by: -1) } }
      .onKeyPress(.rightArrow) { handled { model.move(by: 1) } }
      .onKeyPress(.upArrow) { handled { model.move(by: -columns) } }
      .onKeyPress(.downArrow) { handled { model.move(by: columns) } }
      .onKeyPress(.space) { handled { model.playOrStop() } }
      .onKeyPress(.return) { handled { model.playOrStop() } }
      .onCopyCommand {
        guard let sound = model.selectedSound, let item = NSItemProvider(contentsOf: model.url(for: sound)) else { return [] }
        return [item]
      }
      .onChange(of: model.selectedID) { _, id in
        guard let id else { return }
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
      }
      .onAppear { focused = true }
    }
  }

  private func handled(_ action: () -> Void) -> KeyPress.Result {
    focused = true
    action()
    return .handled
  }
}

struct SectionHeader: View {
  let category: SoundCategory
  let count: Int

  var body: some View {
    HStack(spacing: 10) {
      CategoryIcon(category: category.id, size: 22)
      Text(category.name)
        .font(Typography.bodyStrong)
      Text(category.summary)
        .font(Typography.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      Spacer()
      Text("\(count)")
        .font(Typography.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity)
    .background(Surface.canvas.opacity(0.94))
  }
}

struct SoundTile: View {
  @Environment(AppModel.self) private var model
  let sound: Sound
  @State private var hovering = false

  var body: some View {
    let style = CategoryStyle(sound.category)
    let isSelected = model.selectedID == sound.id
    let isPlaying = model.playingID == sound.id

    VStack(alignment: .leading, spacing: 8) {
      Group {
        if isPlaying {
          TimelineView(.animation) { _ in
            WaveformView(peaks: model.peaks(of: sound), color: style.color, progress: model.progress(of: sound.id))
          }
        } else {
          WaveformView(peaks: model.peaks(of: sound), color: style.color)
        }
      }
      .frame(height: 40)

      VStack(alignment: .leading, spacing: 2) {
        Text(sound.name)
          .font(Typography.tile)
          .lineLimit(1)
        HStack {
          Text(sound.id)
            .font(Typography.mono)
          Spacer()
          Text(sound.formattedDuration)
            .font(Typography.caption)
            .monospacedDigit()
        }
        .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(Surface.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(isSelected ? style.color : hovering ? Color.primary.opacity(0.18) : Surface.hairline, lineWidth: isSelected ? 2 : 1)
    }
    .shadow(color: .black.opacity(isSelected ? 0.12 : 0.04), radius: isSelected ? 8 : 3, y: isSelected ? 3 : 1)
    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .onHover { hovering = $0 }
    .onTapGesture { model.select(sound) }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(sound.name), \(sound.id), \(sound.formattedDuration)")
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    .accessibilityAction { model.select(sound) }
    .onDrag {
      NSItemProvider(contentsOf: model.url(for: sound)) ?? NSItemProvider()
    }
    .contextMenu {
      SoundActions(sound: sound)
    }
    .help("\(sound.name): click to play, drag into a folder or an Xcode project to copy the WAV file")
  }
}

/// What you can do with a sound, in its context menu and in the Sound menu.
struct SoundActions: View {
  @Environment(AppModel.self) private var model
  let sound: Sound

  var body: some View {
    Button("Play") { model.select(sound) }
    Divider()
    Button("Export…") { model.export(sound) }
    Button("Copy File") { model.copyFile(sound) }
    Button("Copy ID") { model.copy(sound.id) }
    Button("Copy Export Command") { model.copy(model.exportCommand(for: sound)) }
    Divider()
    Button("Show in Finder") { model.revealInFinder(sound) }
    if sound.sfxrURL != nil {
      Button("Open in sfxr.me") { model.openInSfxr(sound) }
    }
  }
}
