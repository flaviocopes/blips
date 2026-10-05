import BlipsCore
import Foundation

enum Commands {
  static let all: [Spec] = [categories, list, show, play, path, export, generate]

  static let categories = Spec(
    name: "categories",
    usage: "categories [--json]",
    summary: "List the categories, with how many sounds each has"
  ) { arguments in
    let (store, library) = try load()
    if arguments.json {
      try printJSON(library.categories.map { CategoryOutput($0, count: library.count(in: $0)) })
      return
    }
    let width = library.categories.map(\.id.count).max() ?? 0
    for group in SoundCategory.Group.allCases {
      let categories = library.categories.filter { $0.group == group }
      guard !categories.isEmpty else { continue }
      print(group.title)
      for category in categories {
        let count = String(library.count(in: category)).leftPadded(to: 5)
        print("  \(category.id.padding(toLength: width, withPad: " ", startingAt: 0)) \(count)  \(category.summary)")
      }
      print()
    }
    print("\(library.sounds.count) sounds in \(library.categories.count) categories, from seed \(library.seed), in \(store.folder.path)")
  }

  static let list = Spec(
    name: "list",
    usage: "list [--category <category>] [--tag <tag>] [--search <words>] [--limit <n>] [--json]",
    summary: "List sounds, by category, tag or words in their name",
    options: ["--category", "--tag", "--search", "--limit"],
    details: """
      Tags describe how a sound sounds: low or high, soft (sine), retro (square), buzzy (sawtooth),
      noisy (noise), rising or falling, short or long, repeating and vibrato. Combos are tagged
      stacked or sequence, plus the categories of their parts. Jingles are tagged major or minor,
      fast or slow, and harmony when a second voice plays.

      Examples:
        blips list --category success
        blips list --category notification --tag soft --json
        blips list --category sent --search "soft pop"
        blips list --category fanfare --tag harmony
      """
  ) { arguments in
    let (store, library) = try load()
    let category = try arguments.value("--category").map { try findCategory($0, in: library).id }
    var sounds = library.sounds(category: category, tag: arguments.value("--tag"), matching: arguments.value("--search"))
    if let limit = try arguments.number("--limit") {
      sounds = Array(sounds.prefix(limit))
    }
    if arguments.json {
      try printJSON(sounds.map { SoundOutput($0, store: store, librarySeed: library.seed) })
      return
    }
    guard !sounds.isEmpty else {
      print("No sounds match.")
      return
    }
    let width = sounds.map(\.id.count).max() ?? 0
    for sound in sounds {
      let words = Set(sound.name.lowercased().split(separator: " ").map(String.init))
      let tags = sound.tags.filter { !words.contains($0) }
      print("\(sound.id.padding(toLength: width, withPad: " ", startingAt: 0))  \(seconds(sound.duration))  \(sound.name)  [\(tags.joined(separator: ", "))]")
    }
  }

  static let show = Spec(
    name: "show",
    usage: "show <sound> [--json]",
    summary: "Show a sound's file, tags and jsfxr parameters, or what a combo or jingle is made of"
  ) { arguments in
    let (store, library) = try load()
    guard let id = arguments.positionals.first else { throw CLIError("Which sound? Usage: blips show <sound>") }
    let sound = try findSound(id, in: library)
    if arguments.json {
      try printJSON(SoundOutput(sound, store: store, librarySeed: library.seed, withParams: true))
      return
    }
    let category = library.category(sound.category)
    print("\(sound.id): \(sound.name)")
    print("Category  \(category?.name ?? sound.category): \(category?.summary ?? "")")
    print("Library   seed \(library.seed)")
    print("Tags      \(sound.tags.joined(separator: ", "))")
    print("Length    \(seconds(sound.duration))")
    if let parts = sound.parts, parts.contains(where: { $0.sound != nil }) {
      print("Made of   \(parts.map { "\($0.sound ?? "?") at \(seconds($0.start))" }.joined(separator: ", "))")
    } else if let parts = sound.parts {
      print("Notes     \(parts.map(\.params.noteName).joined(separator: " "))")
    }
    if let params = sound.params {
      print("Pitch     \(Int(params.startFrequency.rounded())) Hz at the start")
    }
    print("File      \(store.url(for: sound).path)")
    if let url = sound.sfxrURL, let params = sound.params {
      print("Edit      \(url.absoluteString)")
      print("jsfxr     \(params.json)")
    }
  }

  static let play = Spec(
    name: "play",
    usage: "play <sound or category>...",
    summary: "Play sounds, one after the other",
    details: """
      Examples:
        blips play success-003
        blips play click-001 click-002 click-003
        blips play notification
      """
  ) { arguments in
    let (store, library) = try load()
    let sounds = try resolve(arguments.positionals, in: library, usage: "blips play <sound or category>...")
    for sound in sounds {
      if !arguments.json {
        print("\(sound.id)  \(seconds(sound.duration))  \(sound.name)")
      }
      try run("/usr/bin/afplay", [store.url(for: sound).path])
    }
  }

  static let path = Spec(
    name: "path",
    usage: "path [<sound>] [--json]",
    summary: "Print the library folder, or a sound's WAV file"
  ) { arguments in
    let store = LibraryStore()
    var url = store.folder
    if let id = arguments.positionals.first {
      let (_, library) = try load()
      url = store.url(for: try findSound(id, in: library))
    }
    if arguments.json {
      try printJSON(["path": url.path])
    } else {
      print(url.path)
    }
  }

  static let export = Spec(
    name: "export",
    usage: "export <sound or category>... --to <folder> [--name <file name>] [--format wav|m4a|caf|aiff] [--seed <n>] [--json]",
    summary: "Copy sounds into a folder, like an app's resources",
    options: ["--to", "--name", "--format", "--seed"],
    details: """
      Files are named after the sound, like success-003.wav. --name renames a single sound, so an app
      can call it what it is. --format converts the sound with afconvert. WAV works in Mac, iOS and web
      apps and starts right away. m4a (AAC) makes long sounds smaller, but adds a few milliseconds of
      silence at the start. Existing files are replaced.

      An ID names a different sound in a library made from another seed. --seed makes sure the library
      is the one you mean, and stops with an error when it isn't.

      Examples:
        blips export success-003 --to Resources/Sounds --name saved.wav
        blips export click-002 error-005 --to public/sounds --format m4a
        blips export fanfare-012 --seed 48213 --to Resources/Sounds
      """
  ) { arguments in
    let (store, library) = try load()
    if let wanted = try seed(arguments), wanted != library.seed {
      throw CLIError("These sounds are from seed \(library.seed), not \(wanted). Run 'blips generate --seed \(wanted)' first.")
    }
    guard let folder = arguments.value("--to") else { throw CLIError("Where to? Add --to <folder>.") }
    let sounds = try resolve(arguments.positionals, in: library, usage: "blips export <sound or category>... --to <folder>")
    let format = (arguments.value("--format") ?? "wav").lowercased()
    guard let conversion = ExportFormat(rawValue: format) else {
      throw CLIError("--format takes wav, m4a, caf or aiff, not “\(format)”.")
    }
    let name = arguments.value("--name")
    if name != nil, sounds.count > 1 {
      throw CLIError("--name only works with one sound, and this exports \(sounds.count).")
    }

    let destination = URL(filePath: (folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    var exported: [[String: String]] = []
    for sound in sounds {
      var file = name ?? sound.id
      if (file as NSString).pathExtension.isEmpty {
        file += ".\(conversion.fileExtension)"
      }
      let target = destination.appending(path: file)
      try? FileManager.default.removeItem(at: target)
      if conversion == .wav {
        try FileManager.default.copyItem(at: store.url(for: sound), to: target)
      } else {
        try run("/usr/bin/afconvert", conversion.afconvertArguments + [store.url(for: sound).path, target.path])
      }
      exported.append(["id": sound.id, "path": target.path])
    }
    if arguments.json {
      try printJSON(exported)
    } else {
      exported.forEach { print($0["path"]!) }
    }
  }

  static let generate = Spec(
    name: "generate",
    usage: "generate [--seed <n> | --seed random] [--json]",
    summary: "Generate the library with jsfxr, replacing the one there",
    options: ["--seed"],
    details: """
      Rolls each category's sounds one after the other, and keeps a roll only when it's clearly
      different from every sound already in the category. A category ends after \(LibraryGenerator.maximumPerCategory) sounds, or
      when it runs out of new ones, so categories have different sizes. Each sound comes from the
      seed, its category and its number, so generating again gives the same sounds.

      The main library comes from seed 1. Another --seed gives a whole different library, and
      --seed random picks a new one each time. Note the seed down to get back to those sounds.

      Examples:
        blips generate
        blips generate --seed random
        blips generate --seed 48213
      """
  ) { arguments in
    let seed = try seed(arguments) ?? LibraryGenerator.defaultSeed
    let store = LibraryStore()
    let start = Date()
    let showProgress = !arguments.json && isatty(STDERR_FILENO) == 1
    let library = try LibraryGenerator.generate(seed: seed, store: store) { progress in
      if showProgress, progress.sounds % 25 == 0 {
        let line = "\rGenerating: \(progress.sounds) sounds, \(progress.categoriesDone) of \(progress.categories) categories done"
        FileHandle.standardError.write(Data(line.utf8))
      }
    }
    if showProgress {
      FileHandle.standardError.write(Data("\r\u{1B}[K".utf8))
    }
    if arguments.json {
      try printJSON(GenerateOutput(count: library.sounds.count, categories: library.categories.count, seed: seed, path: store.folder.path))
      return
    }
    let time = String(format: "%.1f", Date().timeIntervalSince(start))
    print("Generated \(library.sounds.count) sounds in \(library.categories.count) categories from seed \(seed) in \(time) s, in \(store.folder.path)")
  }

  /// The --seed option: a number, or `random` for a new one.
  static func seed(_ arguments: Arguments) throws -> UInt32? {
    guard let text = arguments.value("--seed") else { return nil }
    if text == "random" { return LibraryGenerator.randomSeed() }
    guard let seed = UInt32(text) else { throw CLIError("--seed takes a number or random, not “\(text)”.") }
    return seed
  }
}

// MARK: - Helpers

extension Commands {
  static func load() throws -> (LibraryStore, Library) {
    let store = LibraryStore()
    guard let library = try store.load() else {
      throw CLIError("There's no library in \(store.folder.path) yet. Run 'blips generate' to make it.")
    }
    return (store, library)
  }

  static func findSound(_ id: String, in library: Library) throws -> Sound {
    guard let sound = library.sound(id) else {
      throw CLIError("There's no sound '\(id)'. Run 'blips list' to see them.")
    }
    return sound
  }

  static func findCategory(_ name: String, in library: Library) throws -> SoundCategory {
    guard let category = library.category(name) else {
      let names = library.categories.map(\.id).joined(separator: ", ")
      throw CLIError("There's no '\(name)' category. The categories are \(names).")
    }
    return category
  }

  /// Sound IDs and categories, as sounds, in the order given.
  static func resolve(_ names: [String], in library: Library, usage: String) throws -> [Sound] {
    guard !names.isEmpty else { throw CLIError("Which sounds? Usage: \(usage)") }
    return try names.flatMap { name -> [Sound] in
      if let sound = library.sound(name) { return [sound] }
      if let category = library.category(name) { return library.sounds(category: category.id) }
      throw CLIError("There's no sound or category '\(name)'. Run 'blips categories' or 'blips list' to see them.")
    }
  }

  static func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(filePath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw CLIError("\((executable as NSString).lastPathComponent) failed with status \(process.terminationStatus).")
    }
  }

  static func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    print(String(decoding: try encoder.encode(value), as: UTF8.self))
  }

  static func seconds(_ duration: Double) -> String {
    String(format: "%.2fs", duration)
  }
}

enum ExportFormat: String {
  case wav, m4a, caf, aiff

  var fileExtension: String { rawValue }

  var afconvertArguments: [String] {
    switch self {
    case .wav: []
    case .m4a: ["-f", "m4af", "-d", "aac", "-b", "128000"]
    case .caf: ["-f", "caff", "-d", "LEI16"]
    case .aiff: ["-f", "AIFF", "-d", "BEI16"]
    }
  }
}

struct CategoryOutput: Encodable {
  let id: String
  let name: String
  let summary: String
  let count: Int

  init(_ category: SoundCategory, count: Int) {
    id = category.id
    name = category.name
    summary = category.summary
    self.count = count
  }
}

struct SoundOutput: Encodable {
  let id: String
  let name: String
  let category: String
  let tags: [String]
  let duration: Double
  let path: String
  let sfxr: String?
  /// The seed of the library the sound is from. The same ID names another sound in a library from another seed.
  let librarySeed: UInt32
  let params: SoundParams?
  let parts: [Part]?

  init(_ sound: Sound, store: LibraryStore, librarySeed: UInt32, withParams: Bool = false) {
    self.librarySeed = librarySeed
    id = sound.id
    name = sound.name
    category = sound.category
    tags = sound.tags
    duration = sound.duration
    path = store.url(for: sound).path
    sfxr = sound.sfxrURL?.absoluteString
    params = withParams ? sound.params : nil
    parts = withParams ? sound.parts : nil
  }
}

struct GenerateOutput: Encodable {
  let count: Int
  let categories: Int
  let seed: UInt32
  let path: String
}

extension String {
  func leftPadded(to width: Int) -> String {
    String(repeating: " ", count: max(0, width - count)) + self
  }
}
