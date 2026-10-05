# Blips

A Mac app and a `blips` command with a library of about 6,000 8-bit sound effects made with [jsfxr](https://github.com/chr15m/jsfxr), each clearly different from the others in its category, in 26 categories in four groups: app interfaces (click, blip, pop, toggle, success, error, notification, swoosh), games (coin, power up, jump, laser, explosion, hit), combos of two library sounds (sent, received, trash, confirm, reward, impact, zap) and jingles, short tunes on a scale (fanfare, game over, countdown, startup, alarm). Other apps take their sounds from it: an agent finds candidates with `blips list`, a person listens to them in the app or with `blips play`, and `blips export` copies the one they pick into the app.

A Swift package with no Xcode project and no Swift dependencies. jsfxr runs inside JavaScriptCore, so nothing needs Node at runtime.

- `Sources/BlipsCore`: all the logic.
  - `JSFXRSource.swift` is jsfxr's `riffwave.js` and `sfxr.js` from npm, unchanged, written by `Scripts/update-jsfxr.sh`. Don't edit it by hand.
  - `Synth` loads jsfxr into a `JSContext` and replaces `Math.random` with a seeded generator (mulberry32) before every call, so a seed always rolls the same preset and renders the same noise. It reads the samples straight out of a `Float32Array`.
  - `SoundParams` is jsfxr's parameters, encoded with jsfxr's own JSON keys. `Units` turns seconds, Hz, notes and intervals into jsfxr's 0...1 slider values.
  - `Categories.swift` has `SoundCategory`, `Recipe` and the interface and game recipes. A recipe has a kind: `single` (a jsfxr preset, or parameters built from ranges), `combo` or `jingle`, plus the longest a sound can be. `SeededRandom` is the recipes' random generator.
  - `Combos.swift` has the combo recipes. Each picks library sounds with `Pick` and returns them as `Layer`s, with a start time and a volume.
  - `Jingles.swift` has the jingle recipes, `Voice` (how every note sounds), `Jingle` (notes on a grid of steps) and `Phrase` (the melodies).
  - `LibraryGenerator` makes each category on its own worker with its own `Synth`: single sounds and jingles first, then combos, made of the single sounds. `makeCategory` rolls a category's sounds in order and keeps a roll only when its `Fingerprint` is at least `threshold` (0.4) from every sound already kept. A category ends at 400 sounds, or after `patience` (60) rolls in a row that don't make it. `makeCandidate` makes one roll, seeded from the library seed, the category, the number and the attempt, and masters it in `finish`. `render(_:synth:)` renders any sound again from what `library.json` keeps of it. `Describe` names and tags sounds.
  - `Fingerprint` describes a sound in a few numbers: the spectral centroid and the loudness at 16 moments, how tonal it is, and its length. `distance(to:)` adds up their differences, so about 1 is an octave apart all along, a different loudness shape, a tone against noise, or four times as long.
  - `ExactMath` has sin, cos, log2 and exp2 made of basic arithmetic. See "Sound IDs never change".
  - `Library.swift` has `Sound`, `Part` (a library sound in a combo, or a note in a jingle), `Library` (lookup and filtering) and `LibraryStore`.
  - `WaveFile` writes and reads 16-bit WAV files, `Waveform` makes the peaks the app draws, and `Spectrogram` measures pitch over time with the Goertzel algorithm on log-spaced bands, for the inspector.
- `Sources/BlipsCLI`: the `blips` command. `BlipsCommand.swift` parses arguments and prints help, `Commands.swift` has each command, `Capabilities.swift` has the agent manifest.
- `Sources/BlipsApp`: the SwiftUI app. `AppModel` holds the library, the selection and playback (`AVAudioPlayer`), and caches the waveforms and spectrograms. It works out the sounds shown, their sections and an index by ID only when the library or the sidebar change, since redraws would otherwise filter thousands of sounds each time. `ContentView` has the split view, the sidebar, its footer with the seed, and the Generate sheet, which makes the main library, a new one from a random seed, or one from a seed you type. `SoundGrid` has the tiles, the keyboard and dragging out, and `SoundInspector` the selected sound with its waveform, spectrogram, tags and ways to use it, then jsfxr's parameters drawn as sliders, what a combo is made of (`ComboTimeline`, with rows that play each part) or the notes of a jingle (`PianoRoll`). `Theme.swift` has the colors, and a color and SF Symbol for each category. `CommandLineTool` and `AgentSkill` are the menu items that link the command into `~/.local/bin` and install the skill. `AppUpdater.swift` checks GitHub Releases for updates and installs them. It's a copy of a template shared by several apps, so don't edit it here.
- `skill/blips/SKILL.md`: the agent skill. `build-app.sh` puts it in the app, and the app copies it to `~/.agents/skills/blips` from the menu, and again on launch when an update changed it.
- `Scripts/`: `build-app.sh`, `build-release.sh`, `Blips.entitlements`, `render-icon.swift`, `render-banner.swift`, `screenshot.sh` with `screenshot.swift`, and `update-jsfxr.sh`.
- `Tests/BlipsCoreTests`: Swift Testing tests for the core.
- `docs/`: the README's banner and screenshots.

## Build and test

Requirements: macOS 14+, Swift 6.2 (Xcode 26), and npm only to update jsfxr.

```bash
swift build                      # build everything (debug)
swift test                       # the core tests, must pass before committing
swift run BlipsApp               # run the app from source
swift run blips help             # the command line tool
./Scripts/build-app.sh           # universal release build, dist/Blips.app, with blips in Contents/Helpers
./Scripts/build-release.sh       # dist/Blips-<version>.zip, notarized when the Developer ID is in the keychain
swift Scripts/render-icon.swift  # Assets/AppIcon.png
./Scripts/screenshot.sh <library folder>   # docs/screenshot-light.png and -dark.png, success-002 selected
swift Scripts/render-banner.swift          # docs/banner.png, from docs/screenshot-dark.png
./Scripts/update-jsfxr.sh 1.4.1  # vendor another jsfxr version from npm
```

Set `BLIPS_HOME=/tmp/blips-test` to use another library folder. Blips → Install Command Line Tool links `~/.local/bin/blips` to the command inside the app.

## Sound IDs never change

Apps keep the files they exported, but their AGENTS.md files note which Blips ID each sound came from, so `click-003` has to render the same sound forever, on every Mac. Sound N of a category depends on the sounds before it, since it had to be different from them, so a single number computed differently anywhere changes the rest of the category. The tests check that a category comes out the same twice, that a bigger limit keeps its first sounds, and that every kind of sound renders again bit for bit from its JSON. The whole library comes out byte-identical on Intel and Apple silicon, and with or without the JIT.

- Everything computed before jsfxr renders, and every fingerprint, uses basic arithmetic, `squareRoot()` and `ExactMath`, never `pow`, `log2`, `sin`, `cos` or Accelerate. The system's versions round differently in the last digit on Intel, and that's enough to flip a fingerprint distance across the threshold: when toggle picked its pitches with `pow`, the Intel library was different. Swift doesn't fuse multiplications and additions on its own, so plain arithmetic is safe. To check, build `Sources/BlipsCore/*.swift` with a small `main.swift` for `-target arm64-apple-macos14` and `-target x86_64-apple-macos14`, run both, and compare.
- Add new categories at the end of `Recipe.all`, never in the middle.
- Combos pick their parts among the first `Combo.choices` (150) sounds of each category, so growing a category doesn't change them. Each library sound goes in one combo of a category at most, so a combo category ends when it runs out of parts.
- Changing a recipe, a melody in `Phrase`, `Fingerprint`, `threshold`, `Describe`, `finish`, `mix`, the seed formula in `makeCandidate` or the jsfxr version changes sounds that already exist. Changing a single-sound recipe also changes the combos made from it. Do it only on purpose, and say so in the changelog in `Capabilities.swift`.

## How it works

- The library is `~/Library/Application Support/Blips/library.json` plus `sounds/<category>/<id>.wav`. `generate` renders into `.staging` and swaps the folder in when every category is done. It makes about 6,000 sounds in 14 s, in 300 MB, half of it jingles, which last 1 to 2 s. Categories have different sizes: from 48 (reward) to 400. `library.json` loads in about 0.1 s, and the app reads it again only when its modification date changed.
- The main library comes from seed 1, and sound IDs and packs refer to it. `generate --seed random` (`LibraryGenerator.randomSeed()`, up to 999,999 so it's easy to note down) or the app's Generate sheet make a whole different library, and the same ID names another sound there. `library.json` keeps the library's seed. `categories`, `show`, the JSON of `list` and `show`, and the app's sidebar show it, and the export command the app shows includes `--seed` when it isn't 1. `export --seed` refuses to copy from a library with another seed.
- A single sound in `library.json` keeps its seed, its jsfxr parameters and their base58 form, so it can be rendered again, pasted into `sfxr.toAudio()`, or opened at `https://sfxr.me/#<base58>` to make a variation. A combo or a jingle keeps its `parts` instead, each with its parameters, seed, start time and volume. A combo part also names the library sound it comes from, and is finished like that sound before mixing. Jingle notes are mixed as jsfxr renders them.
- Each roll is wrapped in an `autoreleasepool`. Without it, the JSValues of every render stay alive until the worker ends, with the sample arrays they point to, and generating takes three times the memory.
- The threshold of 0.4 comes from comparing pairs of success sounds: at 0.1 they're copies, at 0.2 the same note with a fourth instead of a fifth, at 0.3 the same sound a whole tone up, at 0.4 a different note and jump, or a different wave.
- A roll that comes out silent, shorter than 20 ms or longer than its category allows is rolled again with the next attempt's seed.
- `finish` masters jsfxr's output: it removes the DC offset that square waves with an uneven duty leave, brings every sound to the same loudness (an RMS of 0.18 over its loudest 50 ms) unless that pushes a sample past 0.9, then fades the first 1 ms and the last 5 ms.
- The app reloads the library when it becomes active, so a `blips generate` in the terminal shows up right away. It plays sounds with `AVAudioPlayer`, the command with `afplay`, and `export --format` converts with `afconvert`.
- `build-app.sh` signs both binaries with `Scripts/Blips.entitlements`, which allows JIT. Without it, JavaScriptCore runs jsfxr in its interpreter, 8 times slower, and that includes the debug builds from `swift build`, so time generation with `dist/Blips.app/Contents/Helpers/blips`.

## Working on the code

- Add logic to `BlipsCore` with a test. Keep `AppModel` and the views thin.
- When you add or change a `blips` command, update its help in `Commands.swift`, `skill/blips/SKILL.md` and the manifest in `Capabilities.swift` together. Agents learn the command from the skill and the help.
- Every version bump adds a changelog entry to `Commands.manifest`, newest first. The version is `Blips.version` in `Sources/BlipsCore/Version.swift`.
- Use the colors and fonts in `Theme.swift`. Each category's color and symbol live in `CategoryStyle`, so a new category needs an entry there.
- The icon is drawn by `Scripts/render-icon.swift`. Change a constant and run it again instead of editing the PNG.
- The app has no UI tests. Check visual changes with `./Scripts/screenshot.sh`, which renders the real views from a library you point it at, and by opening `dist/Blips.app`. `open dist/Blips.app --args -select sent-001` opens the app on a sound, so the inspector can be checked without clicking.

## Releases

- Releases are on GitHub, tagged `vX.Y.Z`, with `Blips-X.Y.Z.zip` from `build-release.sh` attached. Use a minor version for a new feature or a change people notice, and a point version for bug fixes. Changing sounds that already exist is a change people notice.
- The in-app updater installs a release only when the tag equals the app's version, the zip has `Blips.app` at the top with the same bundle ID (`com.flaviocopes.blips`), and its signature is valid. It takes the first `.zip` in the release, so attach only that one zip.
- The release notes start with what's new. The update dialog shows them up to the `## Install` heading.
- `build-release.sh` signs with the Developer ID and notarizes when the certificate and the `notary` notarytool profile are on the Mac. Everywhere else, like CI and forks, it signs ad hoc.
