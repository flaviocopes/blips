import Foundation

/// Makes the library with jsfxr. A category's sounds are rolled one after the other, and a roll is
/// kept only when its `Fingerprint` is clearly different from every sound already in the category,
/// so a category ends when it runs out of new sounds. Each roll's seed comes from the library seed,
/// the category, the sound's number and the attempt, so `click-003` comes out the same every time.
public enum LibraryGenerator {
  /// The seed of the main library, the one sound IDs and packs refer to.
  public static let defaultSeed: UInt32 = 1

  /// A seed for a whole new library, short enough to note down and type back in.
  public static func randomSeed() -> UInt32 {
    UInt32.random(in: 2...999_999)
  }
  /// The most sounds a category can have.
  public static let maximumPerCategory = 400
  /// How far apart two sounds of a category have to be: for a chime, about a different note and
  /// jump, or a different wave. Sounds moved up a whole tone are still too close.
  public static let threshold: Float = 0.4
  /// A category is full when this many rolls in a row come out too close to its sounds, or unusable.
  static let patience = 60
  /// Every sound is as loud as this, measured as the RMS of its loudest 50 ms...
  static let loudness: Float = 0.18
  /// ...unless that would push a sample past this.
  static let peak: Float = 0.9
  static let shortest = 0.02

  public static var categories: [SoundCategory] {
    Recipe.all.map(\.category)
  }

  public struct Progress: Sendable {
    public var sounds: Int
    public var categoriesDone: Int
    public var categories: Int

    public init(sounds: Int, categoriesDone: Int, categories: Int) {
      self.sounds = sounds
      self.categoriesDone = categoriesDone
      self.categories = categories
    }
  }

  /// Makes every category, then replaces the library in `store` with them. Single sounds and
  /// jingles come first, then the combos, which are made of single sounds. `progress` is called
  /// from any thread. `limit` caps each category, for tests.
  public static func generate(
    seed: UInt32 = defaultSeed, limit: Int = maximumPerCategory, store: LibraryStore,
    progress: (@Sendable (Progress) -> Void)? = nil
  ) throws -> Library {
    let staging = store.folder.appending(path: ".staging", directoryHint: .isDirectory)
    try? FileManager.default.removeItem(at: staging)
    for recipe in Recipe.all {
      try FileManager.default.createDirectory(
        at: staging.appending(path: "sounds/\(recipe.category.id)"), withIntermediateDirectories: true)
    }
    defer { try? FileManager.default.removeItem(at: staging) }

    let tracker = Tracker(categories: Recipe.all.count, progress: progress)
    // Jingles take the longest, so they start first.
    let jingles = Recipe.all.filter { if case .jingle = $0.kind { true } else { false } }
    let singles = Recipe.all.filter { if case .single = $0.kind { true } else { false } }
    let combos = Recipe.all.filter { if case .combo = $0.kind { true } else { false } }

    let first = try makeCategories(jingles + singles, seed: seed, limit: limit, staging: staging, components: [:], tracker: tracker)
    let components = first.mapValues(\.components)
    let second = try makeCategories(combos, seed: seed, limit: limit, staging: staging, components: components, tracker: tracker)
    let made = first.merging(second) { $1 }
    let sounds = Recipe.all.flatMap { made[$0.category.id]?.sounds ?? [] }

    try FileManager.default.createDirectory(at: store.folder, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: store.soundsFolder)
    try FileManager.default.moveItem(at: staging.appending(path: "sounds"), to: store.soundsFolder)
    let library = Library(seed: seed, jsfxr: JSFXRSource.version, categories: categories, sounds: sounds)
    try store.save(library)
    return library
  }

  /// Makes categories in parallel, each on its own worker with its own `Synth`.
  private static func makeCategories(
    _ recipes: [Recipe], seed: UInt32, limit: Int, staging: URL, components: [String: [Component]], tracker: Tracker
  ) throws -> [String: Made] {
    let results = CategoryResults()
    DispatchQueue.concurrentPerform(iterations: recipes.count) { index in
      do {
        let synth = try Synth()
        let made = try makeCategory(
          recipes[index], limit: limit, librarySeed: seed, synth: synth, components: components
        ) { sound, samples in
          try WaveFile.data(samples).write(to: staging.appending(path: sound.file))
          tracker.addSound()
        }
        results.store(made, for: recipes[index].category.id)
        tracker.finishCategory()
      } catch {
        results.fail(error)
      }
    }
    return try results.all()
  }

  /// A category's sounds, and the first `Combo.choices` of them with their samples, for combos.
  struct Made: Sendable {
    var sounds: [Sound]
    var components: [Component]
  }

  /// Rolls a category's sounds in order, keeping each roll that's clearly different from the
  /// sounds before it, until `limit`, or until `patience` rolls in a row don't make it.
  /// `keep` gets each sound that's kept, with its finished samples.
  static func makeCategory(
    _ recipe: Recipe, limit: Int, librarySeed: UInt32, synth: Synth, components: [String: [Component]],
    keep: (Sound, [Float]) throws -> Void = { _, _ in }
  ) throws -> Made {
    var made = Made(sounds: [], components: [])
    var prints: [Fingerprint] = []
    var used = Set<String>()
    for number in 1...max(limit, 1) {
      var kept: (Sound, [Float])?
      for attempt in 0..<patience {
        // A worker thread drains its autorelease pool only when it finishes, and until then the
        // JSValues of every render keep their sample arrays alive in JavaScriptCore.
        let candidate = try autoreleasepool {
          try makeCandidate(
            recipe, number: number, attempt: attempt, librarySeed: librarySeed, synth: synth, components: components,
            used: used
          )
        }
        guard let (sound, samples) = candidate else { continue }
        let print = Fingerprint(samples)
        if prints.allSatisfy({ print.distance(to: $0) >= threshold }) {
          prints.append(print)
          kept = (sound, samples)
          break
        }
      }
      guard let (sound, samples) = kept else { break }
      try keep(sound, samples)
      made.sounds.append(sound)
      used.formUnion(sound.parts?.compactMap(\.sound) ?? [])
      if number <= Combo.choices, case .single = recipe.kind {
        made.components.append(Component(sound: sound, samples: samples))
      }
    }
    return made
  }

  /// One roll of a sound and its finished samples, or nil when it comes out silent, too short or
  /// too long, or when it's a combo with no library sounds left that fit. `used` lists the library
  /// sounds the category's combos already use: each one goes in a single combo of a category.
  static func makeCandidate(
    _ recipe: Recipe, number: Int, attempt: Int, librarySeed: UInt32, synth: Synth, components: [String: [Component]],
    used: Set<String> = []
  ) throws -> (Sound, [Float])? {
    let category = recipe.category
    let id = String(format: "%@-%03d", category.id, number)
    let seed = fnv1a("\(librarySeed)/\(category.id)/\(number)/\(attempt)")
    var random = SeededRandom(seed: seed)
    let draft: Draft
    do {
      draft = try makeDraft(recipe, seed: seed, random: &random, synth: synth, components: components, used: used)
    } catch is NothingLeft {
      return nil
    }
    let duration = Double(draft.raw.count) / Double(WaveFile.sampleRate)
    guard duration >= shortest, duration <= recipe.longest, draft.raw.contains(where: { abs($0) > 0.02 }) else { return nil }

    let (name, tags) = draft.describe(duration)
    let sound = Sound(
      id: id,
      name: name,
      category: category.id,
      tags: tags,
      duration: rounded(duration),
      file: "sounds/\(category.id)/\(id).wav",
      seed: seed,
      sfxr: try draft.params.map { try synth.base58($0) },
      params: draft.params,
      parts: draft.parts
    )
    return (sound, finish(draft.raw))
  }

  /// A sound before it's finished: its mixed samples, what it's made of, and how to name it once its length is known.
  private struct Draft {
    var raw: [Float]
    var params: SoundParams?
    var parts: [Part]?
    var describe: (Double) -> (name: String, tags: [String])
  }

  private static func makeDraft(
    _ recipe: Recipe, seed: UInt32, random: inout SeededRandom, synth: Synth, components: [String: [Component]],
    used: Set<String>
  ) throws -> Draft {
    let category = recipe.category
    switch recipe.kind {
    case .single(let make):
      let params = try make(&random) { try synth.preset($0, seed: seed) }
      return Draft(raw: try synth.render(params, seed: seed), params: params) { duration in
        let tags = Describe.tags(params, duration: duration)
        return (Describe.name(category, tags: tags), tags)
      }

    case .combo(let make):
      let layers = try make(&random) { random, categoryID, accept in
        try pick(categoryID, accept: accept, random: &random, components: components, used: used)
      }
      let parts = layers.map { layer in
        Part(
          sound: layer.component.sound.id, start: layer.start, duration: layer.component.sound.duration,
          volume: layer.volume, seed: layer.component.sound.seed, params: layer.component.sound.params ?? SoundParams()
        )
      }
      let raw = mix(layers.map { ($0.component.samples, $0.start, $0.volume) })
      let stacked = layers.allSatisfy { $0.start < 0.08 }
      return Draft(raw: raw, parts: parts) { duration in
        Describe.combo(category, of: layers.map(\.component.sound), stacked: stacked, duration: duration)
      }

    case .jingle(let make):
      let jingle = make(&random)
      let notes = try jingle.notes.map { note in (note, try synth.render(note.params, seed: seed)) }
      let parts = notes.map { note, samples in
        Part(
          sound: nil, start: note.start, duration: rounded(Double(samples.count) / Double(WaveFile.sampleRate)),
          volume: note.volume, seed: seed, params: note.params
        )
      }
      let raw = mix(notes.map { ($1, $0.start, $0.volume) })
      return Draft(raw: raw, parts: parts) { duration in
        Describe.jingle(category, jingle, duration: duration)
      }
    }
  }

  /// A library sound for a combo, among the first `Combo.choices` sounds of its category that fit
  /// and that no other combo of the category uses.
  private static func pick(
    _ categoryID: String, accept: (Sound) -> Bool, random: inout SeededRandom, components: [String: [Component]],
    used: Set<String>
  ) throws -> Component {
    let choices = (components[categoryID] ?? []).filter { !used.contains($0.sound.id) && accept($0.sound) }
    guard !choices.isEmpty else { throw NothingLeft() }
    return choices[random.int(choices.count)]
  }

  /// A combo roll found no library sound left for one of its parts.
  private struct NothingLeft: Error {}

  /// Renders a sound again from what the library keeps of it: its parameters and seed, or its parts.
  /// Combo parts are finished like the library sounds they come from, jingle notes are mixed as jsfxr renders them.
  public static func render(_ sound: Sound, synth: Synth) throws -> [Float] {
    if let parts = sound.parts {
      let layers = try parts.map { part in
        let raw = try synth.render(part.params, seed: part.seed)
        return (part.sound == nil ? raw : finish(raw), part.start, part.volume)
      }
      return finish(mix(layers))
    }
    guard let params = sound.params else { throw BlipsError("\(sound.id) has no jsfxr parameters.") }
    return finish(try synth.render(params, seed: sound.seed))
  }

  /// Adds the layers together, each from its start time and at its volume.
  static func mix(_ layers: [(samples: [Float], start: Double, volume: Double)]) -> [Float] {
    let offsets = layers.map { Int(($0.start * Double(WaveFile.sampleRate)).rounded()) }
    let length = zip(offsets, layers).map { $0 + $1.samples.count }.max() ?? 0
    var mixed = [Float](repeating: 0, count: length)
    for (offset, layer) in zip(offsets, layers) {
      let volume = Float(layer.volume)
      for (index, sample) in layer.samples.enumerated() {
        mixed[offset + index] += sample * volume
      }
    }
    return mixed
  }

  static func rounded(_ seconds: Double) -> Double {
    (seconds * 1000).rounded() / 1000
  }

  /// Masters jsfxr's output for use in apps. Removes the DC offset that square waves with an
  /// uneven duty leave, brings every sound to the same loudness, and fades the first 1 ms and the
  /// last 5 ms, so no sound starts or ends on a click, even one jsfxr cuts off at a frequency limit.
  static func finish(_ raw: [Float]) -> [Float] {
    var samples = removeDCOffset(raw)
    let loudest = samples.reduce(0) { max($0, abs($1)) }
    guard loudest > 0 else { return samples }
    let gain = min(loudness / loudestWindowRMS(samples), peak / loudest)

    let fadeIn = min(samples.count, WaveFile.sampleRate / 1000)
    let fadeOut = min(samples.count, WaveFile.sampleRate / 200)
    for index in samples.indices {
      var level = gain
      if index < fadeIn { level *= Float(index) / Float(fadeIn) }
      let remaining = samples.count - index
      if remaining < fadeOut { level *= Float(remaining) / Float(fadeOut) }
      samples[index] *= level
    }
    return samples
  }

  /// A one-pole high-pass filter at about 10 Hz.
  static func removeDCOffset(_ samples: [Float]) -> [Float] {
    var previousInput: Float = 0
    var previousOutput: Float = 0
    return samples.map { sample in
      previousOutput = sample - previousInput + 0.9986 * previousOutput
      previousInput = sample
      return previousOutput
    }
  }

  /// The RMS of the loudest 50 ms window, stepping 10 ms at a time.
  static func loudestWindowRMS(_ samples: [Float]) -> Float {
    let window = min(samples.count, WaveFile.sampleRate / 20)
    let step = WaveFile.sampleRate / 100
    var loudest: Float = 0
    for start in stride(from: 0, through: samples.count - window, by: step) {
      var sum: Float = 0
      for sample in samples[start..<start + window] {
        sum += sample * sample
      }
      loudest = max(loudest, (sum / Float(window)).squareRoot())
    }
    return max(loudest, .leastNonzeroMagnitude)
  }

  static func fnv1a(_ text: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in text.utf8 {
      hash = (hash ^ UInt32(byte)) &* 16_777_619
    }
    return hash
  }

  /// Counts the sounds and categories done, for `progress`.
  private final class Tracker: @unchecked Sendable {
    private let lock = NSLock()
    private var state: Progress
    private let progress: (@Sendable (Progress) -> Void)?

    init(categories: Int, progress: (@Sendable (Progress) -> Void)?) {
      state = Progress(sounds: 0, categoriesDone: 0, categories: categories)
      self.progress = progress
    }

    func addSound() {
      let state = lock.withLock {
        self.state.sounds += 1
        return self.state
      }
      progress?(state)
    }

    func finishCategory() {
      let state = lock.withLock {
        self.state.categoriesDone += 1
        return self.state
      }
      progress?(state)
    }
  }

  /// Collects the categories from the workers.
  private final class CategoryResults: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [String: Made] = [:]
    private var error: Error?

    func store(_ made: Made, for category: String) {
      lock.withLock { self.made[category] = made }
    }

    func fail(_ error: Error) {
      lock.withLock { self.error = self.error ?? error }
    }

    func all() throws -> [String: Made] {
      try lock.withLock {
        if let error { throw error }
        return made
      }
    }
  }
}

/// Names and tags a sound from its parameters, so it can be found by words like "soft" or "rising".
enum Describe {
  static func tags(_ params: SoundParams, duration: Double) -> [String] {
    var tags: [String] = []
    if let pitch = pitch(params) { tags.append(pitch) }
    tags.append(texture(params.wave))
    if let direction = direction(params, duration: duration) { tags.append(direction) }
    tags.append(params.wave.name)
    if duration < 0.15 { tags.append("short") }
    if duration > 0.6 { tags.append("long") }
    if params.repeatSpeed > 0 { tags.append("repeating") }
    if params.vibratoDepth > 0.05 && params.vibratoSpeed > 0.05 { tags.append("vibrato") }
    return tags
  }

  /// Like "High soft rising success": the pitch, texture and direction tags, then the category.
  static func name(_ category: SoundCategory, tags: [String]) -> String {
    let waves = SoundParams.Wave.allCases.map(\.name)
    let words = Array(tags.prefix(while: { !waves.contains($0) })) + [category.name.lowercased()]
    let name = words.joined(separator: " ")
    return name.prefix(1).uppercased() + name.dropFirst()
  }

  static func pitch(_ params: SoundParams) -> String? {
    let hz = params.startFrequency
    return hz < 300 ? "low" : hz > 1200 ? "high" : nil
  }

  static func texture(_ wave: SoundParams.Wave) -> String {
    switch wave {
    case .square: "retro"
    case .sawtooth: "buzzy"
    case .sine: "soft"
    case .noise: "noisy"
    }
  }

  /// Like "Rising swoosh into soft pop", or "Buzzy coin with retro power up" when the parts play together.
  /// The tags are the parts' categories and what they sound like.
  static func combo(_ category: SoundCategory, of sounds: [Sound], stacked: Bool, duration: Double) -> (name: String, tags: [String]) {
    let textures = ["retro", "buzzy", "soft", "noisy"]
    func describe(_ sound: Sound) -> String {
      let word = sound.category == "swoosh"
        ? sound.tags.first { $0 == "rising" || $0 == "falling" }
        : sound.tags.first { textures.contains($0) }
      let name = Recipe.byID[sound.category]?.category.name.lowercased() ?? sound.category
      return [word, name].compactMap { $0 }.joined(separator: " ")
    }
    let name = sounds.map(describe).joined(separator: stacked ? " with " : " into ")

    let skipped = Set(SoundParams.Wave.allCases.map(\.name) + ["short", "long"])
    var tags = [stacked ? "stacked" : "sequence"]
    for tag in sounds.map(\.category) + sounds.flatMap(\.tags) where !skipped.contains(tag) && !tags.contains(tag) {
      tags.append(tag)
    }
    tags += lengthTags(duration)
    return (name.prefix(1).uppercased() + name.dropFirst(), tags)
  }

  /// Like "Fast retro fanfare": the tempo, the texture of the notes, then the category.
  static func jingle(_ category: SoundCategory, _ jingle: Jingle, duration: Double) -> (name: String, tags: [String]) {
    var tags: [String] = []
    if jingle.scale != nil, jingle.step < 0.09 { tags.append("fast") }
    if jingle.scale != nil, jingle.step > 0.2 { tags.append("slow") }
    tags.append(texture(jingle.voice.wave))
    let name = (tags + [category.name.lowercased()]).joined(separator: " ")
    if let scale = jingle.scale { tags.append(scale) }
    if jingle.harmony { tags.append("harmony") }
    tags.append(jingle.voice.wave.name)
    tags += lengthTags(duration)
    if jingle.notes.contains(where: { $0.params.vibratoDepth > 0.05 }) { tags.append("vibrato") }
    return (name.prefix(1).uppercased() + name.dropFirst(), tags)
  }

  static func lengthTags(_ duration: Double) -> [String] {
    duration < 0.15 ? ["short"] : duration > 0.6 ? ["long"] : []
  }

  /// Rising or falling, from the arpeggio when it happens before the sound ends, or else the slide.
  static func direction(_ params: SoundParams, duration: Double) -> String? {
    let arpeggioTime = ((1 - params.arpeggioSpeed) * (1 - params.arpeggioSpeed) * 20000 + 32) / Double(WaveFile.sampleRate)
    if abs(params.arpeggioChange) > 0.05, params.arpeggioSpeed < 1, arpeggioTime < duration {
      return params.arpeggioChange > 0 ? "rising" : "falling"
    }
    if abs(params.frequencySlide) > 0.05 {
      return params.frequencySlide > 0 ? "rising" : "falling"
    }
    return nil
  }
}
