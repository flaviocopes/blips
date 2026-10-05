import BlipsCore
import Foundation

extension Commands {
  /// What `blips capabilities` prints. Add a changelog entry for every release, newest first.
  static let manifest = Manifest(
    name: "blips",
    version: Blips.version,
    summary: "A library of about 6,000 8-bit sound effects made with jsfxr, each clearly different from the others in its category: interface sounds like click, success and error, game sounds, combos like sent and trash, and jingles like fanfare and countdown, to find, play and copy into apps.",
    capabilities: [
      Manifest.Capability(
        description: "List the sound categories: interface sounds, game sounds, combos and jingles",
        command: "blips categories --json"
      ),
      Manifest.Capability(
        description: "Find combos of two sounds for app events, like a swoosh into a pop for a sent message",
        command: "blips list --category sent --json"
      ),
      Manifest.Capability(
        description: "Find short jingles, like victory fanfares, game over tunes, countdowns, startup tunes and alarms",
        command: "blips list --category fanfare --tag harmony --json"
      ),
      Manifest.Capability(
        description: "Find sound effects in a category, by tag like soft or rising, or by words",
        command: "blips list --category success --tag soft --json"
      ),
      Manifest.Capability(
        description: "Play sound effects to hear them before picking one",
        command: "blips play success-003 success-007"
      ),
      Manifest.Capability(
        description: "Copy a sound effect into an app's resources, with the name the app uses",
        command: "blips export success-003 --to Resources/Sounds --name saved.wav"
      ),
      Manifest.Capability(
        description: "Convert sound effects to M4A, CAF or AIFF while copying them, for web or iOS apps",
        command: "blips export notification-002 click-004 --to public/sounds --format m4a"
      ),
      Manifest.Capability(
        description: "Show a sound's file, tags and jsfxr parameters, with a link to edit it on sfxr.me",
        command: "blips show error-004 --json"
      ),
      Manifest.Capability(
        description: "Print the WAV file of a sound, or the library folder",
        command: "blips path click-001"
      ),
      Manifest.Capability(
        description: "Generate the sound library with jsfxr, or a whole new library from a random seed",
        command: "blips generate --seed random"
      ),
    ],
    changelog: [
      Manifest.Release(
        version: "1.0.0",
        date: "2026-10-05",
        changes: [
          "First release: about 6,000 jsfxr sound effects in 26 categories of interface sounds, game sounds, combos and jingles, each clearly different from the others in its category.",
          "Commands to list, show, play, export and generate sounds, with JSON output, and an agent skill.",
          "The same seed gives the same library on every Mac, and --seed random makes a whole new one.",
        ]
      )
    ]
  )

  struct Manifest: Encodable {
    struct Capability: Encodable {
      let description: String
      var command: String? = nil
    }

    struct Release: Encodable {
      let version: String
      let date: String
      let changes: [String]
    }

    let name: String
    let version: String
    let summary: String
    let capabilities: [Capability]
    let changelog: [Release]

    func print(json: Bool) throws {
      if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        Swift.print(String(decoding: try encoder.encode(self), as: UTF8.self))
        return
      }

      Swift.print("\(name) \(version)\n\(summary)\n\nWhat it can do:")
      for capability in capabilities {
        Swift.print("  \(capability.description)")
        if let command = capability.command { Swift.print("    $ \(command)") }
      }
      Swift.print("\nChanges:")
      for release in changelog {
        Swift.print("  \(release.version) (\(release.date))")
        release.changes.forEach { Swift.print("    - \($0)") }
      }
    }
  }
}
