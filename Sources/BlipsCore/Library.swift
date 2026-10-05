import Foundation

public struct Sound: Codable, Hashable, Identifiable, Sendable {
  /// The category and a number, like `click-003`. It stays the same when the library grows.
  public let id: String
  public var name: String
  public var category: String
  public var tags: [String]
  /// In seconds.
  public var duration: Double
  /// The WAV file, relative to the library folder.
  public var file: String
  /// The seed jsfxr rendered the sound with. Together with `params`, it renders the same samples again.
  public var seed: UInt32
  /// The parameters in jsfxr's base58 form, for sfxr.me links. Nil for combos and jingles.
  public var sfxr: String?
  /// Nil for combos and jingles, which are made of `parts`.
  public var params: SoundParams?
  /// What a combo or a jingle is made of: library sounds or notes, mixed at their start times.
  public var parts: [Part]?

  public var sfxrURL: URL? {
    sfxr.map { URL(string: "https://sfxr.me/#\($0)")! }
  }
}

/// One sound in a combo or one note in a jingle.
public struct Part: Codable, Hashable, Sendable {
  /// The library sound a combo part comes from, like `swoosh-042`. Nil for the notes of a jingle.
  public var sound: String?
  /// When the part starts, in seconds from the start of the combo or jingle.
  public var start: Double
  /// How long the part rings, in seconds.
  public var duration: Double
  public var volume: Double
  public var seed: UInt32
  public var params: SoundParams
}

public struct Library: Codable, Hashable, Sendable {
  /// The seed the whole library was generated from. Another seed gives other sounds.
  public var seed: UInt32
  /// The jsfxr version that made the sounds.
  public var jsfxr: String
  public var categories: [SoundCategory]
  public var sounds: [Sound]

  public init(seed: UInt32, jsfxr: String, categories: [SoundCategory], sounds: [Sound]) {
    self.seed = seed
    self.jsfxr = jsfxr
    self.categories = categories
    self.sounds = sounds
  }

  public func sound(_ id: String) -> Sound? {
    sounds.first { $0.id == id.lowercased() }
  }

  /// A category by its ID or its name, in any case: `powerup` or `Power Up`.
  public func category(_ name: String) -> SoundCategory? {
    let key = name.lowercased().filter { !$0.isWhitespace && $0 != "-" }
    return categories.first { $0.id == key || $0.name.lowercased().filter { !$0.isWhitespace } == key }
  }

  public func count(in category: SoundCategory) -> Int {
    sounds.reduce(0) { $0 + ($1.category == category.id ? 1 : 0) }
  }

  /// The sounds in a category, with a tag, and matching every word of `text` in their ID, name,
  /// category or tags. Each filter is skipped when it's nil or empty.
  public func sounds(category: String? = nil, tag: String? = nil, matching text: String? = nil) -> [Sound] {
    let words = (text ?? "").lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
    let tag = tag?.lowercased()
    return sounds.filter { sound in
      if let category, !category.isEmpty, sound.category != category { return false }
      if let tag, !tag.isEmpty, !sound.tags.contains(tag) { return false }
      guard !words.isEmpty else { return true }
      let haystack = ([sound.id, sound.name, sound.category] + sound.tags).joined(separator: " ").lowercased()
      return words.allSatisfy(haystack.contains)
    }
  }
}

/// Reads and writes the library: `library.json` and the WAV files in `sounds/<category>/`, in
/// `~/Library/Application Support/Blips`. Set `BLIPS_HOME` to use another folder.
public struct LibraryStore: Sendable {
  public let folder: URL

  public init(folder: URL = LibraryStore.defaultFolder) {
    self.folder = folder
  }

  public static var defaultFolder: URL {
    if let custom = ProcessInfo.processInfo.environment["BLIPS_HOME"], !custom.isEmpty {
      return URL(filePath: (custom as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    }
    return URL.applicationSupportDirectory.appending(path: "Blips", directoryHint: .isDirectory)
  }

  public var libraryURL: URL {
    folder.appending(path: "library.json")
  }

  public var soundsFolder: URL {
    folder.appending(path: "sounds", directoryHint: .isDirectory)
  }

  public func url(for sound: Sound) -> URL {
    folder.appending(path: sound.file)
  }

  /// The library, or nil when it hasn't been generated yet.
  public func load() throws -> Library? {
    guard FileManager.default.fileExists(atPath: libraryURL.path) else { return nil }
    return try JSONDecoder().decode(Library.self, from: Data(contentsOf: libraryURL))
  }

  /// When `library.json` last changed, to skip reading it again when it didn't.
  public var modified: Date? {
    (try? FileManager.default.attributesOfItem(atPath: libraryURL.path))?[.modificationDate] as? Date
  }

  public func save(_ library: Library) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(library).write(to: libraryURL, options: .atomic)
  }
}
