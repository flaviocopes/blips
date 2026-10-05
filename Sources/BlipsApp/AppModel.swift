import AVFoundation
import AppKit
import BlipsCore
import Observation
import UniformTypeIdentifiers

/// What the sidebar selects: every sound, or one category.
enum SidebarItem: Hashable {
  case all
  case category(String)
}

@Observable
@MainActor
final class AppModel {
  typealias Generation = LibraryGenerator.Progress

  let store = LibraryStore()
  private(set) var library: Library?
  var sidebar: SidebarItem? = .all {
    didSet { refresh() }
  }
  var search = "" {
    didSet { refresh() }
  }
  var selectedID: Sound.ID?
  private(set) var playingID: Sound.ID?
  private(set) var generation: Generation?
  var showsInspector = true
  var showsGenerateSheet = false
  var errorMessage: String?

  /// The sounds shown, and the same sounds grouped by category, worked out when the library,
  /// the sidebar or the search change, not on every redraw: a library holds thousands of sounds.
  private(set) var sounds: [Sound] = []
  private(set) var sections: [(category: SoundCategory, sounds: [Sound])] = []
  private(set) var counts: [String: Int] = [:]

  @ObservationIgnored private var index: [Sound.ID: Sound] = [:]
  @ObservationIgnored private var loadedVersion: Date?
  @ObservationIgnored private var player: AVAudioPlayer?
  @ObservationIgnored private var peakCache: [Sound.ID: [Float]] = [:]
  @ObservationIgnored private var spectrogramCache: [Sound.ID: [[Float]]] = [:]

  /// `open Blips.app --args -select sent-001` opens the app on that sound.
  init() {
    load()
    if let id = UserDefaults.standard.string(forKey: "select"), let sound = index[id] {
      sidebar = .category(sound.category)
      selectedID = sound.id
    }
  }

  /// Reads the library again when `library.json` changed, for when the `blips` command made a new one.
  func load() {
    let modified = store.modified
    guard modified != loadedVersion else { return }
    do {
      let fresh = try store.load()
      loadedVersion = modified
      use(fresh)
    } catch {
      errorMessage = "Blips couldn't read its library in \(store.folder.path): \(error.localizedDescription)"
    }
  }

  private func use(_ fresh: Library?) {
    peakCache = [:]
    spectrogramCache = [:]
    library = fresh
    index = Dictionary(uniqueKeysWithValues: (fresh?.sounds ?? []).map { ($0.id, $0) })
    counts = Dictionary(grouping: fresh?.sounds ?? [], by: \.category).mapValues(\.count)
    if let selectedID, index[selectedID] == nil {
      self.selectedID = nil
    }
    refresh()
  }

  private func refresh() {
    guard let library else {
      sounds = []
      sections = []
      return
    }
    sounds = library.sounds(category: category, matching: search)
    let grouped = Dictionary(grouping: sounds, by: \.category)
    sections = library.categories.compactMap { category in
      grouped[category.id].map { (category, $0) }
    }
  }

  // MARK: - What's shown

  var category: String? {
    if case .category(let id) = sidebar { id } else { nil }
  }

  var selectedSound: Sound? {
    selectedID.flatMap { index[$0] }
  }

  func sound(_ id: Sound.ID) -> Sound? {
    index[id]
  }

  /// Selects and plays a sound, like a part of a combo, switching to its category when it isn't shown.
  func show(_ id: Sound.ID) {
    guard let sound = index[id] else { return }
    if !sounds.contains(where: { $0.id == id }) {
      search = ""
      sidebar = .category(sound.category)
    }
    select(sound)
  }

  var title: String {
    guard let category, let library else { return "All Sounds" }
    return library.category(category)?.name ?? "All Sounds"
  }

  func url(for sound: Sound) -> URL {
    store.url(for: sound)
  }

  /// The loudest sample of 160 slices of the sound, read from its WAV file once.
  func peaks(of sound: Sound) -> [Float] {
    if let cached = peakCache[sound.id] { return cached }
    let peaks = Waveform.peaks(samples(of: sound), count: 160)
    peakCache[sound.id] = peaks
    return peaks
  }

  /// The sound's pitch over time, for the inspector. Only the last few are kept.
  func spectrogram(of sound: Sound) -> [[Float]] {
    if let cached = spectrogramCache[sound.id] { return cached }
    if spectrogramCache.count > 40 { spectrogramCache = [:] }
    let spectrogram = Spectrogram.compute(samples(of: sound), columns: 120, bands: 64)
    spectrogramCache[sound.id] = spectrogram
    return spectrogram
  }

  private func samples(of sound: Sound) -> [Float] {
    (try? WaveFile.samples(in: Data(contentsOf: url(for: sound)))) ?? []
  }

  // MARK: - Playing

  func select(_ sound: Sound) {
    selectedID = sound.id
    play(sound)
  }

  /// Selects and plays the sound `offset` places away from the selected one.
  func move(by offset: Int) {
    let sounds = self.sounds
    guard !sounds.isEmpty else { return }
    let index = sounds.firstIndex { $0.id == selectedID }.map { $0 + offset } ?? 0
    select(sounds[min(max(index, 0), sounds.count - 1)])
  }

  func play(_ sound: Sound) {
    player?.stop()
    do {
      let player = try AVAudioPlayer(contentsOf: url(for: sound))
      player.play()
      self.player = player
      playingID = sound.id
      Task { [weak self] in
        try? await Task.sleep(for: .seconds(player.duration + 0.05))
        guard let self, self.player === player else { return }
        self.playingID = nil
        self.player = nil
      }
    } catch {
      errorMessage = "Blips couldn't play \(sound.id): \(error.localizedDescription)"
    }
  }

  func stop() {
    player?.stop()
    player = nil
    playingID = nil
  }

  func playOrStop() {
    if playingID != nil {
      stop()
    } else if let sound = selectedSound {
      play(sound)
    } else {
      move(by: 0)
    }
  }

  /// How far the sound has played, from 0 to 1, or nil when it isn't playing.
  func progress(of id: Sound.ID) -> Double? {
    guard playingID == id, let player, player.duration > 0 else { return nil }
    return player.currentTime / player.duration
  }

  // MARK: - Using sounds

  func copyFile(_ sound: Sound) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([url(for: sound) as NSURL])
  }

  /// The command that copies a sound into an app. It names the seed when the library isn't the main
  /// one, since the same ID is another sound in another library.
  func exportCommand(for sound: Sound) -> String {
    let seed = library?.seed ?? LibraryGenerator.defaultSeed
    let seedOption = seed == LibraryGenerator.defaultSeed ? "" : " --seed \(seed)"
    return "blips export \(sound.id)\(seedOption) --to ."
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }

  func revealInFinder(_ sound: Sound) {
    NSWorkspace.shared.activateFileViewerSelecting([url(for: sound)])
  }

  func revealLibrary() {
    NSWorkspace.shared.activateFileViewerSelecting([store.libraryURL])
  }

  func openInSfxr(_ sound: Sound) {
    if let url = sound.sfxrURL {
      NSWorkspace.shared.open(url)
    }
  }

  /// Saves one sound under a name you pick, like `saved.wav`.
  func export(_ sound: Sound) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(sound.id).wav"
    panel.allowedContentTypes = [.wav]
    panel.message = "Export \(sound.name)"
    guard panel.runModal() == .OK, let target = panel.url else { return }
    copyFiles([(sound, target)])
  }

  /// Copies sounds into a folder you pick, named after their IDs.
  func export(_ sounds: [Sound], name: String) {
    guard !sounds.isEmpty else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.prompt = "Export"
    panel.message = "Choose a folder for the \(sounds.count) \(name) sounds"
    guard panel.runModal() == .OK, let folder = panel.url else { return }
    copyFiles(sounds.map { ($0, folder.appending(path: "\($0.id).wav")) })
  }

  private func copyFiles(_ files: [(Sound, URL)]) {
    do {
      for (sound, target) in files {
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url(for: sound), to: target)
      }
      NSWorkspace.shared.activateFileViewerSelecting(files.map(\.1))
    } catch {
      errorMessage = "Blips couldn't export: \(error.localizedDescription)"
    }
  }

  // MARK: - Generating

  func generate(seed: UInt32 = LibraryGenerator.defaultSeed) {
    guard generation == nil else { return }
    stop()
    generation = Generation(sounds: 0, categoriesDone: 0, categories: LibraryGenerator.categories.count)
    let store = self.store
    Task.detached(priority: .userInitiated) { [weak self] in
      do {
        let library = try LibraryGenerator.generate(seed: seed, store: store) { progress in
          guard progress.sounds % 25 == 0 else { return }
          Task { @MainActor in
            if self?.generation != nil { self?.generation = progress }
          }
        }
        await self?.finishGenerating(library)
      } catch {
        await self?.failGenerating(error)
      }
    }
  }

  private func finishGenerating(_ library: Library) {
    generation = nil
    showsGenerateSheet = false
    loadedVersion = store.modified
    use(library)
  }

  private func failGenerating(_ error: Error) {
    generation = nil
    errorMessage = "Blips couldn't generate the library: \(error.localizedDescription)"
  }
}
