import Foundation
import Testing

@testable import BlipsCore

@Suite struct LibraryTests {
  /// Small categories of single sounds, to make combos from.
  static func components(_ categories: [String], limit: Int, synth: Synth) throws -> [String: [Component]] {
    var components: [String: [Component]] = [:]
    for id in categories {
      components[id] = try LibraryGenerator.makeCategory(
        Recipe.byID[id]!, limit: limit, librarySeed: 1, synth: synth, components: [:]
      ).components
    }
    return components
  }

  @Test func generatesTheLibrary() throws {
    let store = LibraryStore(folder: FileManager.default.temporaryDirectory.appending(path: "blips-test-\(UUID())"))
    defer { try? FileManager.default.removeItem(at: store.folder) }

    let library = try LibraryGenerator.generate(limit: 3, store: store)
    #expect(library.sounds.first?.id == "click-001")
    #expect(Set(library.sounds.map(\.id)).count == library.sounds.count)
    #expect(try store.load() == library)
    for recipe in Recipe.all {
      let count = library.sounds(category: recipe.category.id).count
      if case .combo = recipe.kind {
        #expect(count <= 3)
      } else {
        #expect(count == 3, "\(recipe.category.id) has \(count) sounds")
      }
    }

    for sound in library.sounds {
      let samples = try WaveFile.samples(in: Data(contentsOf: store.url(for: sound)))
      #expect(abs(Double(samples.count) / 44100 - sound.duration) < 0.001)
      let peak = samples.reduce(0) { max($0, abs($1)) }
      let loudness = LibraryGenerator.loudestWindowRMS(samples)
      #expect(peak <= 0.91)
      #expect(abs(loudness - 0.18) < 0.02 || peak > 0.88, "\(sound.id) has loudness \(loudness) and peak \(peak)")
      #expect(abs(samples[0]) < 0.001)
      #expect(abs(samples[samples.count - 1]) < 0.01)
    }
  }

  @Test func soundsInACategoryAreClearlyDifferent() throws {
    let synth = try Synth()
    let made = try LibraryGenerator.makeCategory(Recipe.success, limit: 8, librarySeed: 1, synth: synth, components: [:])
    let prints = try made.sounds.map { Fingerprint(try LibraryGenerator.render($0, synth: synth)) }
    for i in prints.indices {
      for j in prints.indices where j > i {
        #expect(prints[i].distance(to: prints[j]) >= LibraryGenerator.threshold)
      }
    }
  }

  @Test func growingACategoryKeepsItsFirstSounds() throws {
    let synth = try Synth()
    let small = try LibraryGenerator.makeCategory(Recipe.toggle, limit: 3, librarySeed: 1, synth: synth, components: [:])
    let big = try LibraryGenerator.makeCategory(Recipe.toggle, limit: 6, librarySeed: 1, synth: synth, components: [:])
    let otherSeed = try LibraryGenerator.makeCategory(Recipe.toggle, limit: 3, librarySeed: 2, synth: synth, components: [:])
    #expect(Array(big.sounds.prefix(3)) == small.sounds)
    #expect(otherSeed.sounds != small.sounds)
  }

  @Test func soundsFitTheirCategoryLength() throws {
    let synth = try Synth()
    let components = try Self.components(
      ["swoosh", "pop", "notification", "success", "click", "blip", "hit", "explosion", "coin", "powerup", "laser"],
      limit: 12, synth: synth)
    for recipe in Recipe.all {
      let made = try LibraryGenerator.makeCategory(recipe, limit: 2, librarySeed: 1, synth: synth, components: components)
      #expect(!made.sounds.isEmpty, "\(recipe.category.id) made no sounds")
      for sound in made.sounds {
        #expect(sound.duration <= recipe.longest, "\(sound.id) lasts \(sound.duration) s")
      }
    }
  }

  @Test func combosUseEachLibrarySoundOnce() throws {
    let synth = try Synth()
    let components = try Self.components(["swoosh", "pop"], limit: 16, synth: synth)
    let made = try LibraryGenerator.makeCategory(Recipe.sent, limit: 4, librarySeed: 1, synth: synth, components: components)
    #expect(made.sounds.count >= 2)
    let parts = made.sounds.flatMap { $0.parts ?? [] }.compactMap(\.sound)
    #expect(Set(parts).count == parts.count)

    let sent = made.sounds[0]
    let ids = try #require(sent.parts).compactMap(\.sound)
    #expect(sent.params == nil && sent.sfxr == nil)
    #expect(ids.map { $0.split(separator: "-")[0] } == ["swoosh", "pop"])
    #expect(sent.tags.contains("sequence") && sent.tags.contains("swoosh"))
  }

  @Test func jinglesAreNotesOnAScale() throws {
    let synth = try Synth()
    let fanfare = try LibraryGenerator.makeCategory(Recipe.fanfare, limit: 1, librarySeed: 1, synth: synth, components: [:]).sounds[0]
    let notes = try #require(fanfare.parts)
    #expect(notes.count >= 4)
    #expect(notes.allSatisfy { $0.sound == nil })
    #expect(fanfare.tags.contains("major"))
    #expect(fanfare.name.hasSuffix("fanfare"))
  }

  @Test func everySoundRendersAgainFromTheLibrary() throws {
    let synth = try Synth()
    let components = try Self.components(["swoosh", "pop"], limit: 16, synth: synth)
    for recipe in [Recipe.success, Recipe.sent, Recipe.fanfare] {
      var kept: [(Sound, [Float])] = []
      _ = try LibraryGenerator.makeCategory(recipe, limit: 1, librarySeed: 1, synth: synth, components: components) {
        kept.append(($0, $1))
      }
      let (sound, samples) = try #require(kept.first)
      let decoded = try JSONDecoder().decode(Sound.self, from: JSONEncoder().encode(sound))
      #expect(try LibraryGenerator.render(decoded, synth: synth) == samples, "\(sound.id) renders differently")
    }
  }

  @Test func filtersSounds() throws {
    let synth = try Synth()
    let sounds = try Recipe.all.prefix(6).flatMap {
      try LibraryGenerator.makeCategory($0, limit: 1, librarySeed: 1, synth: synth, components: [:]).sounds
    }
    let library = Library(seed: 1, jsfxr: "1.4.1", categories: LibraryGenerator.categories, sounds: sounds)

    #expect(library.sounds(category: "success").map(\.id) == ["success-001"])
    #expect(library.sounds(matching: "SUCCESS 001").map(\.id) == ["success-001"])
    #expect(library.category("Power Up")?.id == "powerup")
    #expect(library.category("power-up")?.id == "powerup")
    #expect(library.sound("CLICK-001") != nil)
    let tag = sounds[0].tags[0]
    #expect(library.sounds(tag: tag).contains(sounds[0]))
  }

  @Test func namesSoundsFromTheirTags() {
    let category = SoundCategory(id: "success", name: "Success", summary: "", group: .interface)
    #expect(Describe.name(category, tags: ["high", "soft", "rising", "sine", "short"]) == "High soft rising success")
    #expect(Describe.name(category, tags: ["retro", "square"]) == "Retro success")
  }
}
