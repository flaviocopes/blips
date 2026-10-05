import Foundation

public struct SoundCategory: Codable, Hashable, Identifiable, Sendable {
  public enum Group: String, Codable, Sendable, CaseIterable {
    case interface, game, combo, jingle

    public var title: String {
      switch self {
      case .interface: "Interface"
      case .game: "Game"
      case .combo: "Combos"
      case .jingle: "Jingles"
      }
    }
  }

  public let id: String
  public let name: String
  public let summary: String
  public var group: Group = .interface
}

/// How the sounds of a category are made, with the ranges that make them fit the category.
struct Recipe: Sendable {
  enum Kind: Sendable {
    /// One jsfxr sound: a preset, rolled with the sound's seed by the closure it gets, or parameters built from scratch.
    case single(@Sendable (inout SeededRandom, (String) throws -> SoundParams) throws -> SoundParams)
    /// Library sounds stacked or one after the other. `Pick` finds a library sound for each part.
    case combo(@Sendable (inout SeededRandom, Pick) throws -> [Layer])
    /// A short melody of jsfxr notes.
    case jingle(@Sendable (inout SeededRandom) -> Jingle)
  }

  let category: SoundCategory
  /// The longest a sound of the category can be, in seconds. Longer rolls are rolled again.
  var longest = 3.0
  let kind: Kind

  init(category: SoundCategory, longest: Double = 3, kind: Kind) {
    self.category = category
    self.longest = longest
    self.kind = kind
  }

  init(
    category: SoundCategory, longest: Double = 3,
    make: @escaping @Sendable (inout SeededRandom, (String) throws -> SoundParams) throws -> SoundParams
  ) {
    self.init(category: category, longest: longest, kind: .single(make))
  }
}

extension Recipe {
  /// The order here is the order of the categories everywhere. Add new ones at the end, so the
  /// sounds of the existing ones keep their numbers.
  static let all: [Recipe] = [click, blip, pop, toggle, success, error, notification, swoosh] + game + combos + jingles

  static let byID: [String: Recipe] = Dictionary(uniqueKeysWithValues: all.map { ($0.category.id, $0) })

  /// The major pentatonic notes from G4 to C6, in semitones from A4, for the chimes.
  static let wideChimeNotes: [Double] = [-2, 0, 3, 5, 7, 10, 12, 15]

  /// Pitch ratios for the jumps in two-note sounds: a fourth and a fifth, plus a major third and an octave.
  static let fourthAndFifth: [Double] = [4.0 / 3, 3.0 / 2]
  static let risingIntervals: [Double] = [5.0 / 4, 4.0 / 3, 3.0 / 2, 2]
  static let fallingIntervals: [Double] = risingIntervals.map { 1 / $0 }
  static let tritone: Double = 2.0.squareRoot()

  static let click = Recipe(
    category: SoundCategory(id: "click", name: "Click", summary: "Short clicks and taps for buttons and keys"),
    longest: 0.2
  ) { random, preset in
    if random.chance(0.5) {
      return try preset("click")
    }
    var p = SoundParams()
    p.wave = random.pick([.square, .noise, .sine])
    p.duty = random.frnd(0.6)
    p.baseFrequency = random.range(0.55...0.95)
    p.frequencySlide = random.range(-0.4...0.1)
    p.sustain = Units.time(random.range(0.004...0.015))
    p.decay = Units.time(random.range(0.02...0.07))
    p.punch = random.frnd(0.5)
    p.highPassCutoff = random.range(0.1...0.4)
    return p
  }

  static let blip = Recipe(
    category: SoundCategory(id: "blip", name: "Blip", summary: "Menu blips for hover, select and navigation"),
    longest: 0.3
  ) { random, preset in
    var p = try preset("blipSelect")
    p.baseFrequency = min(max(p.baseFrequency + random.range(-0.1...0.3), 0.12), 0.95)
    if random.chance(0.3) {
      p.wave = .sine
    }
    if random.chance(0.35) {
      p.frequencySlide = random.range(-0.3...0.3)
    }
    if random.chance(0.4) {
      p.sustain *= 0.6
      p.decay *= 0.6
    }
    return p
  }

  static let pop = Recipe(
    category: SoundCategory(id: "pop", name: "Pop", summary: "Bubbly pops for new messages and items"),
    longest: 0.3
  ) { random, _ in
    var p = SoundParams()
    p.wave = random.chance(0.7) ? .sine : .square
    p.duty = random.range(0.3...0.7)
    p.baseFrequency = random.range(0.25...0.45)
    p.frequencySlide = random.range(0.25...0.55)
    p.sustain = Units.time(random.range(0.01...0.04))
    p.decay = Units.time(random.range(0.05...0.14))
    p.punch = random.range(0.2...0.6)
    p.lowPassCutoff = random.chance(0.5) ? random.range(0.5...0.9) : 1
    p.highPassCutoff = random.frnd(0.1)
    return p
  }

  static let toggle = Recipe(
    category: SoundCategory(id: "toggle", name: "Toggle", summary: "Two-note flicks for switches and checkboxes"),
    longest: 0.3
  ) { random, _ in
    var p = SoundParams()
    p.wave = random.pick([.square, .square, .sine, .sawtooth])
    p.duty = p.wave == .sawtooth ? 1 : random.frnd(0.6)
    p.baseFrequency = Units.note(random.range(-5...17))
    let up = random.chance(0.6)
    if random.chance(0.7) {
      let interval = random.pick(risingIntervals)
      p.arpeggioChange = Units.arpeggio(ratio: up ? interval : 1 / interval)
      p.arpeggioSpeed = Units.delay(random.range(0.015...0.05))
    } else {
      p.frequencySlide = up ? random.range(0.3...0.6) : random.range(-0.6 ... -0.3)
    }
    p.sustain = Units.time(random.range(0.02...0.07))
    p.decay = Units.time(random.range(0.02...0.1))
    p.highPassCutoff = random.frnd(0.25)
    return p
  }

  static let success = Recipe(
    category: SoundCategory(id: "success", name: "Success", summary: "Rising chimes for done, saved and correct"),
    longest: 1
  ) { random, _ in
    var p = SoundParams()
    p.wave = random.pick([.sine, .square, .square, .sawtooth])
    p.duty = p.wave == .sawtooth ? 1 : random.frnd(0.6)
    p.baseFrequency = Units.note(random.pick(wideChimeNotes))
    p.sustain = Units.time(random.range(0.06...0.22))
    p.decay = Units.time(random.range(0.15...0.45))
    p.punch = random.frnd(0.6)
    switch random.int(4) {
    case 0, 1:
      p.arpeggioChange = Units.arpeggio(ratio: random.pick(risingIntervals))
      p.arpeggioSpeed = Units.delay(random.range(0.04...0.14))
    case 2:
      p.frequencySlide = random.range(0.08...0.3)
    default:
      // Rings twice, jumping up each time.
      p.arpeggioChange = Units.arpeggio(ratio: random.pick(risingIntervals))
      p.arpeggioSpeed = Units.delay(random.range(0.03...0.07))
      p.repeatSpeed = Units.delay(random.range(0.12...0.2))
    }
    if random.chance(0.3) {
      p.vibratoDepth = random.range(0.02...0.1)
      p.vibratoSpeed = random.range(0.3...0.7)
    }
    if p.wave == .square, random.chance(0.4) {
      p.dutySweep = random.range(-0.3...0.3)
    }
    if p.wave == .sawtooth {
      p.lowPassCutoff = random.range(0.35...0.8)
    }
    return p
  }

  static let error = Recipe(
    category: SoundCategory(id: "error", name: "Error", summary: "Low buzzes for failures and wrong input"),
    longest: 1
  ) { random, _ in
    var p = SoundParams()
    p.wave = random.pick([.square, .square, .sawtooth])
    p.duty = p.wave == .sawtooth ? 1 : random.range(0.3...0.7)
    p.baseFrequency = Units.frequency(hz: random.range(140...260))
    p.sustain = Units.time(random.range(0.12...0.25))
    p.decay = Units.time(random.range(0.1...0.25))
    switch random.int(3) {
    case 0:
      p.arpeggioChange = Units.arpeggio(ratio: 1 / random.pick(fourthAndFifth + [tritone]))
      p.arpeggioSpeed = Units.delay(random.range(0.08...0.14))
    case 1:
      p.frequencySlide = random.range(-0.3 ... -0.15)
    default:
      let period = random.range(0.1...0.15)
      p.repeatSpeed = Units.delay(period)
      p.sustain = Units.time(period * 1.2)
      p.decay = Units.time(period)
    }
    p.lowPassCutoff = random.range(0.35...0.7)
    p.punch = random.frnd(0.3)
    return p
  }

  static let notification = Recipe(
    category: SoundCategory(id: "notification", name: "Notification", summary: "Chimes that ask for attention, for alerts and reminders"),
    longest: 1.5
  ) { random, _ in
    var p = SoundParams()
    p.wave = random.pick([.sine, .sine, .square, .sawtooth])
    p.duty = p.wave == .sawtooth ? 1 : random.frnd(0.6)
    p.baseFrequency = Units.note(random.pick(wideChimeNotes + [17, 19]))
    p.arpeggioChange = Units.arpeggio(ratio: random.pick(risingIntervals + fallingIntervals))
    p.arpeggioSpeed = Units.delay(random.range(0.08...0.2))
    p.sustain = Units.time(random.range(0.1...0.3))
    p.decay = Units.time(random.range(0.25...0.7))
    p.punch = random.frnd(0.5)
    if random.chance(0.3) {
      p.attack = Units.time(random.range(0.02...0.08))
    }
    if random.chance(0.4) {
      p.repeatSpeed = Units.delay(random.range(0.18...0.4))
    }
    if random.chance(0.3) {
      p.vibratoDepth = random.range(0.02...0.1)
      p.vibratoSpeed = random.range(0.3...0.7)
    }
    if random.chance(0.15) {
      p.frequencySlide = random.range(-0.15...0.15)
    }
    if p.wave == .sawtooth {
      p.lowPassCutoff = random.range(0.35...0.8)
    }
    return p
  }

  static let swoosh = Recipe(
    category: SoundCategory(id: "swoosh", name: "Swoosh", summary: "Whooshes for transitions, sending and sliding panels"),
    longest: 1
  ) { random, _ in
    var p = SoundParams()
    p.wave = .noise
    p.baseFrequency = random.range(0.2...0.5)
    p.frequencySlide = random.chance(0.5) ? random.range(0.05...0.25) : random.range(-0.25 ... -0.05)
    p.attack = Units.time(random.range(0.06...0.18))
    p.sustain = Units.time(random.range(0.03...0.1))
    p.decay = Units.time(random.range(0.12...0.3))
    p.lowPassCutoff = random.range(0.2...0.5)
    p.lowPassSweep = random.range(-0.15...0.25)
    p.lowPassResonance = random.range(0.3...0.8)
    p.highPassCutoff = random.frnd(0.15)
    if random.chance(0.3) {
      p.flangerOffset = random.range(0.05...0.2)
      p.flangerSweep = random.range(-0.1...0.1)
    }
    return p
  }

  /// jsfxr's coin preset is always a sawtooth, so some coins switch to a square or a sine.
  static let coin = Recipe(
    category: SoundCategory(id: "coin", name: "Coin", summary: "Coin pickups and rewards", group: .game)
  ) { random, preset in
    var p = try preset("pickupCoin")
    if random.chance(0.5) {
      p.wave = random.pick([.square, .square, .sine])
      p.duty = random.frnd(0.6)
    }
    return p
  }

  /// jsfxr's own game presets, unchanged.
  static let game: [Recipe] = [coin] + [
    ("powerup", "Power Up", "Rising power-ups, level ups and unlocks", "powerUp"),
    ("jump", "Jump", "Springy jumps and bounces", "jump"),
    ("laser", "Laser", "Laser shots and zaps", "laserShoot"),
    ("explosion", "Explosion", "Explosions, crashes and crunches", "explosion"),
    ("hit", "Hit", "Hits, hurts and thuds", "hitHurt"),
  ].map { id, name, summary, presetName in
    Recipe(category: SoundCategory(id: id, name: name, summary: summary, group: .game)) { _, preset in
      try preset(presetName)
    }
  }
}

/// SplitMix64, seeded per sound, for the recipes' choices.
struct SeededRandom {
  private var state: UInt64

  init(seed: UInt32) {
    state = UInt64(seed) &* 0x9E37_79B9_7F4A_7C15
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  mutating func unit() -> Double {
    Double(next() >> 11) / Double(1 << 53)
  }

  /// A number on 0..<range, like jsfxr's `frnd`.
  mutating func frnd(_ range: Double) -> Double {
    unit() * range
  }

  mutating func range(_ range: ClosedRange<Double>) -> Double {
    range.lowerBound + unit() * (range.upperBound - range.lowerBound)
  }

  mutating func int(_ count: Int) -> Int {
    Int(next() % UInt64(count))
  }

  mutating func chance(_ probability: Double) -> Bool {
    unit() < probability
  }

  mutating func pick<T>(_ items: [T]) -> T {
    items[int(items.count)]
  }
}
