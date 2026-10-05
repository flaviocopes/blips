import Foundation

/// A library sound with its finished samples, as a part of a combo.
struct Component: Sendable {
  let sound: Sound
  let samples: [Float]
}

/// A part of a combo: a library sound, when it starts, and how loud it plays.
struct Layer: Sendable {
  let component: Component
  let start: Double
  let volume: Double
}

/// Finds a library sound in a category for a combo, among its first `Combo.choices` sounds,
/// rolling until `accept` likes the sound.
typealias Pick = (inout SeededRandom, String, (Sound) -> Bool) throws -> Component

enum Combo {
  /// Combos only use the first sounds of each category, so growing a category doesn't change them.
  static let choices = 150
}

extension Recipe {
  static let combos: [Recipe] = [sent, received, trash, confirm, reward, impact, zap]

  static let sent = combo(
    "sent", "Sent", "A swoosh that lands on a pop, for sending a message or a file"
  ) { random, pick in
    let swoosh = try pick(&random, "swoosh") { $0.tags.contains("rising") }
    let pop = try pick(&random, "pop") { _ in true }
    return [
      Layer(component: swoosh, start: 0, volume: random.range(0.6...0.85)),
      Layer(component: pop, start: swoosh.sound.duration * random.range(0.55...0.85), volume: 1),
    ]
  }

  static let received = combo(
    "received", "Received", "A pop and a chime, for an incoming message"
  ) { random, pick in
    let pop = try pick(&random, "pop") { _ in true }
    let chime = try pick(&random, random.chance(0.7) ? "notification" : "success") { $0.duration < 0.9 }
    return [
      Layer(component: pop, start: 0, volume: 1),
      Layer(component: chime, start: pop.sound.duration * random.range(0.5...0.9), volume: random.range(0.7...0.9)),
    ]
  }

  static let trash = combo(
    "trash", "Trash", "A falling swoosh into a crunch, for deleting and throwing away"
  ) { random, pick in
    let swoosh = try pick(&random, "swoosh") { $0.tags.contains("falling") }
    let crunch = try pick(&random, random.chance(0.5) ? "hit" : "explosion") { $0.duration < 0.4 }
    return [
      Layer(component: swoosh, start: 0, volume: random.range(0.6...0.85)),
      Layer(component: crunch, start: swoosh.sound.duration * random.range(0.6...0.9), volume: 1),
    ]
  }

  static let confirm = combo(
    "confirm", "Confirm", "A click or a blip followed by a chime, for buttons that finish something"
  ) { random, pick in
    let click = try pick(&random, random.chance(0.6) ? "click" : "blip") { _ in true }
    let chime = try pick(&random, "success") { _ in true }
    return [
      Layer(component: click, start: 0, volume: random.range(0.8...1)),
      Layer(component: chime, start: click.sound.duration * random.range(0.6...1) + random.range(0...0.04), volume: 1),
    ]
  }

  static let reward = combo(
    "reward", "Reward", "A coin and a power-up stacked, for unlocks and achievements"
  ) { random, pick in
    let coin = try pick(&random, "coin") { $0.duration > 0.1 }
    let powerUp = try pick(&random, "powerup") { _ in true }
    return [
      Layer(component: coin, start: 0, volume: 1),
      Layer(component: powerUp, start: random.range(0...0.06), volume: random.range(0.6...0.9)),
    ]
  }

  static let impact = combo(
    "impact", "Impact", "A hit with an explosion under it, for heavy hits and crashes"
  ) { random, pick in
    let hit = try pick(&random, "hit") { _ in true }
    let explosion = try pick(&random, "explosion") { $0.duration < 1.2 }
    return [
      Layer(component: hit, start: 0, volume: 1),
      Layer(component: explosion, start: random.range(0...0.02), volume: random.range(0.6...0.9)),
    ]
  }

  static let zap = combo(
    "zap", "Zap", "A laser shot and the hit that follows"
  ) { random, pick in
    let laser = try pick(&random, "laser") { _ in true }
    let hit = try pick(&random, "hit") { _ in true }
    return [
      Layer(component: laser, start: 0, volume: 1),
      Layer(component: hit, start: laser.sound.duration * random.range(0.7...1) + random.range(0...0.05), volume: random.range(0.7...1)),
    ]
  }

  private static func combo(
    _ id: String, _ name: String, _ summary: String,
    make: @escaping @Sendable (inout SeededRandom, Pick) throws -> [Layer]
  ) -> Recipe {
    Recipe(category: SoundCategory(id: id, name: name, summary: summary, group: .combo), longest: 2.5, kind: .combo(make))
  }
}
