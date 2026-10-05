import Foundation

/// How every note of a jingle sounds.
struct Voice: Sendable {
  var wave: SoundParams.Wave
  var duty: Double
  var lowPass: Double
  var punch: Double
  /// How long a note rings out after it's held, relative to its length.
  var release: Double

  static func roll(_ random: inout SeededRandom, gentle: Bool = false) -> Voice {
    let wave: SoundParams.Wave = gentle ? random.pick([.sine, .sine, .square]) : random.pick([.square, .square, .sine, .sawtooth])
    return Voice(
      wave: wave,
      duty: wave == .sawtooth ? 1 : random.frnd(0.6),
      lowPass: wave == .sawtooth ? random.range(0.4...0.7) : 1,
      punch: random.range(0.1...0.4),
      release: random.range(0.8...1.6)
    )
  }

  /// A soft sine an octave below the melody, for the second voice.
  static let bass = Voice(wave: .sine, duty: 0, lowPass: 1, punch: 0.1, release: 1.2)

  func note(_ semitones: Double, length: Double) -> SoundParams {
    var p = SoundParams()
    p.wave = wave
    p.duty = duty
    p.lowPassCutoff = lowPass
    p.punch = punch
    p.baseFrequency = Units.note(semitones)
    p.sustain = Units.time(length * 0.6)
    p.decay = Units.time(length * release)
    return p
  }
}

struct Note: Sendable {
  var params: SoundParams
  var start: Double
  var volume: Double
}

/// A melody being written: notes placed on a grid of steps, `step` seconds long.
struct Jingle: Sendable {
  var voice: Voice
  var step: Double
  var scale: String?
  var notes: [Note] = []
  var harmony = false

  mutating func add(_ semitones: Double, at beat: Double, length: Double, volume: Double = 1, voice: Voice? = nil) {
    let params = (voice ?? self.voice).note(semitones, length: length * step)
    notes.append(Note(params: params, start: beat * step, volume: volume))
  }

  /// Plays notes one after the other from `beat`: each is a pitch in semitones above `root` and a length
  /// in steps. Returns the pitch, start and length of the last one.
  @discardableResult
  mutating func melody(_ melody: [Phrase.Step], root: Double, from beat: Double = 0) -> (pitch: Double, beat: Double, length: Double) {
    var beat = beat
    var last = (pitch: root, beat: beat, length: 1.0)
    for (interval, length) in melody {
      add(root + interval, at: beat, length: length)
      last = (root + interval, beat, length)
      beat += length
    }
    return last
  }

  /// Doubles the last note an octave below, in a soft second voice.
  mutating func harmonize(_ last: (pitch: Double, beat: Double, length: Double), volume: Double) {
    add(last.pitch - 12, at: last.beat, length: last.length, volume: volume, voice: .bass)
    harmony = true
  }

  mutating func shapeLastMelodyNote(_ change: (inout SoundParams) -> Void) {
    guard let index = notes.lastIndex(where: { $0.volume == 1 }) else { return }
    change(&notes[index].params)
  }
}

/// Melodies, as (semitones above the root, length in steps).
enum Phrase {
  typealias Step = (Double, Double)

  static let fanfares: [[Step]] = [
    [(0, 1), (4, 1), (7, 1), (12, 3)],
    [(7, 1), (7, 1), (7, 1), (12, 4)],
    [(0, 1), (4, 1), (7, 1), (4, 1), (7, 1), (12, 4)],
    [(0, 0.5), (0, 0.5), (0, 0.5), (0, 1.5), (-4, 1.5), (-2, 1.5), (0, 1), (-2, 0.5), (0, 4)],
    [(0, 1), (7, 1), (12, 1), (16, 1), (19, 3)],
    [(12, 1), (7, 1), (12, 1), (16, 3)],
    [(0, 1), (2, 1), (4, 1), (7, 1), (9, 1), (12, 3)],
  ]

  static let gameOvers: [[Step]] = [
    [(0, 1), (-1, 1), (-2, 1), (-3, 4)],
    [(7, 1), (3, 1), (0, 1), (-5, 3)],
    [(12, 1), (10, 1), (7, 1), (3, 1), (0, 4)],
    [(0, 2), (-5, 2), (-9, 2), (-12, 3)],
    [(3, 1), (2, 1), (0, 1), (-2, 1), (-5, 1), (-9, 3)],
  ]

  /// The major pentatonic scale over two octaves, for startup melodies.
  static let pentatonic: [Double] = [0, 2, 4, 7, 9, 12, 14, 16, 19]
}

extension Recipe {
  static let jingles: [Recipe] = [fanfare, gameOver, countdown, startup, alarm]

  /// Roots in semitones from A4, from C4 to C5.
  static let roots: [Double] = [-9, -7, -5, -4, -2, 0, 3]

  static let fanfare = jingle("fanfare", "Fanfare", "Short victory tunes for wins and finished tasks") { random in
    var jingle = Jingle(voice: .roll(&random), step: random.range(0.07...0.13), scale: "major")
    let last = jingle.melody(random.pick(Phrase.fanfares), root: random.pick(roots))
    if random.chance(0.5) {
      jingle.harmonize(last, volume: random.range(0.45...0.6))
    }
    if random.chance(0.3) {
      let depth = random.range(0.03...0.08)
      jingle.shapeLastMelodyNote {
        $0.vibratoDepth = depth
        $0.vibratoSpeed = 0.5
      }
    }
    return jingle
  }

  static let gameOver = jingle("gameover", "Game Over", "Falling tunes for losing and game over") { random in
    var jingle = Jingle(voice: .roll(&random), step: random.range(0.14...0.24), scale: "minor")
    let last = jingle.melody(random.pick(Phrase.gameOvers), root: random.pick([-2, 0, 3, 5]))
    if random.chance(0.3) {
      jingle.harmonize(last, volume: random.range(0.45...0.6))
    }
    let wobble = random.chance(0.7) ? random.range(0.1...0.2) : 0
    let droop = random.chance(0.4) ? random.range(-0.12 ... -0.05) : 0
    jingle.shapeLastMelodyNote {
      $0.vibratoDepth = wobble
      $0.vibratoSpeed = wobble > 0 ? 0.5 : 0
      $0.frequencySlide = droop
    }
    return jingle
  }

  static let countdown = jingle("countdown", "Countdown", "Beeps and a go, for countdowns and timers") { random in
    var jingle = Jingle(voice: .roll(&random), step: random.range(0.22...0.45))
    let pitch = random.pick(Phrase.pentatonic.map { $0 - 2 })
    let beeps = random.pick([2, 3, 3, 4])
    let beep = random.range(0.05...0.16) / jingle.step
    let climb = random.chance(0.3) ? random.pick([2.0, 4, 5]) : 0
    for index in 0..<beeps {
      jingle.add(pitch + Double(index) * climb, at: Double(index), length: beep)
    }
    jingle.add(pitch + Double(beeps) * climb + random.pick([4.0, 5, 7, 12]), at: Double(beeps), length: random.range(1...2))
    if random.chance(0.3) {
      let depth = random.range(0.05...0.15)
      jingle.shapeLastMelodyNote {
        $0.vibratoDepth = depth
        $0.vibratoSpeed = 0.55
      }
    }
    return jingle
  }

  static let startup = jingle("startup", "Startup", "Little intro tunes for launching an app") { random in
    var jingle = Jingle(voice: .roll(&random, gentle: true), step: random.range(0.09...0.15), scale: "major")
    let root = random.pick([-9.0, -7, -5, -2, 0])
    var degree = random.int(3)
    var beat = 0.0
    for _ in 0..<(3 + random.int(4)) {
      let length = random.chance(0.25) ? 0.5 : 1
      jingle.add(root + Phrase.pentatonic[degree], at: beat, length: length)
      beat += length
      degree = min(max(degree + random.pick([1, 1, 2, -1]), 0), Phrase.pentatonic.count - 2)
    }
    let ending = random.pick([5, 5, 3, 7])
    jingle.add(root + Phrase.pentatonic[ending], at: beat, length: random.range(3...4))
    if random.chance(0.6) {
      jingle.add(root - 12, at: 0, length: beat + 3, volume: random.range(0.35...0.5), voice: .bass)
      jingle.harmony = true
    }
    return jingle
  }

  static let alarm = jingle("alarm", "Alarm", "Urgent repeating beeps for alarms and warnings") { random in
    var voice = Voice.roll(&random)
    voice.release = random.range(0.3...0.6)
    var jingle = Jingle(voice: voice, step: random.range(0.06...0.16))
    let high = random.range(5...20).rounded()
    switch random.int(5) {
    case 0:
      // High and low, back and forth.
      let low = high - random.pick([3.0, 4, 5, 7, 12])
      for index in 0..<random.pick([4, 6, 8]) {
        jingle.add(index % 2 == 0 ? high : low, at: Double(index), length: 0.9)
      }
    case 1:
      // Groups of quick beeps with a gap between them.
      let beeps = random.pick([2, 3, 4])
      for group in 0..<random.pick([2, 3]) {
        for index in 0..<beeps {
          jingle.add(high, at: Double(group * (beeps + 2) + index), length: 0.7)
        }
      }
    case 2:
      // A siren: each note slides up, then the next one down.
      jingle.step *= 2.5
      let slide = random.range(0.15...0.3)
      for index in 0..<4 {
        jingle.add(high - 5, at: Double(index), length: 1)
        jingle.notes[jingle.notes.count - 1].params.frequencySlide = index % 2 == 0 ? slide : -slide
      }
    case 3:
      // A low buzzer.
      jingle.voice = Voice(wave: .sawtooth, duty: 1, lowPass: random.range(0.3...0.6), punch: 0.2, release: 0.3)
      jingle.step *= 2
      for index in 0..<random.pick([2, 3, 4]) {
        jingle.add(high - 24, at: Double(index), length: 0.8)
      }
    default:
      // A ladder of notes going up, twice.
      let rungs = random.pick([3, 4, 5])
      let interval = random.pick([2.0, 3, 4, 5])
      for round in 0..<2 {
        for rung in 0..<rungs {
          jingle.add(high - 7 + Double(rung) * interval, at: Double(round * (rungs + 1) + rung), length: 0.8)
        }
      }
    }
    return jingle
  }

  private static func jingle(
    _ id: String, _ name: String, _ summary: String, make: @escaping @Sendable (inout SeededRandom) -> Jingle
  ) -> Recipe {
    Recipe(category: SoundCategory(id: id, name: name, summary: summary, group: .jingle), longest: 4, kind: .jingle(make))
  }
}
