---
name: blips
description: Find, play and copy 8-bit sound effects and jingles into an app with the blips command. Chip Pops is a library of about 6,000 sounds made with jsfxr, each clearly different from the others in its category, in categories for app interfaces (click, blip, pop, toggle, success, error, notification, swoosh), games (coin, power up, jump, laser, explosion, hit), combos of two sounds (sent, received, trash, confirm, reward, impact, zap) and jingles (fanfare, game over, countdown, startup, alarm). Use when an app or a game needs sound effects, UI sounds, feedback sounds or a short tune, like a click, a message sent sound, an error, a notification, a victory fanfare or a countdown, and when asked to pick, play, export or generate sounds with Chip Pops.
---

# Chip Pops

Chip Pops is a Mac app and a `blips` command with a library of about 6,000 8-bit sound effects made with [jsfxr](https://sfxr.me). The generator keeps a sound only when it's clearly different from the others in its category, so categories have different sizes, from about 50 to 400. Every sound has an ID like `success-003`, a name like "Soft rising success", a category and tags. IDs never change: the library is generated from a seed, so `success-003` is the same sound on every Mac.

Run `blips help` for the commands, and `blips help <command>` for the options of one. Every command takes `--json`.

## Add sounds to an app

Match each event in the app to a category:

| Event | Category |
|---|---|
| Buttons, keys, taps | `click` |
| Hover, menus, moving a selection | `blip` |
| A new message or item | `pop` |
| Switches and checkboxes | `toggle` |
| Done, saved, correct | `success` |
| Failed, wrong input | `error` |
| Alerts and reminders | `notification` |
| Transitions, sliding panels | `swoosh` |
| A message or a file sent | `sent` (a swoosh into a pop) |
| A message received | `received` (a pop into a chime) |
| Deleting, throwing away | `trash` (a falling swoosh into a crunch) |
| A button that finishes something | `confirm` (a click into a chime) |
| Unlocks, achievements | `reward` (a coin and a power-up together) |
| Winning, a task done | `fanfare` |
| Losing, game over | `gameover` |
| Countdowns, timers starting | `countdown` |
| Launching the app | `startup` |
| Alarms, urgent warnings | `alarm` |

Games also have `coin`, `powerup`, `jump`, `laser`, `explosion`, `hit`, `impact` (a hit with an explosion) and `zap` (a laser and a hit). Run `blips categories` to see them all.

Then list the candidates and read their tags:

```bash
blips list --category success --json
blips list --category click --tag soft
```

Tags say how a sound sounds: `soft` (a sine wave, the calmest), `retro` (square, chiptune), `buzzy` (sawtooth), `noisy` (noise), `low` or `high`, `rising` or `falling`, `short` (under 0.15 s) or `long` (over 0.6 s), `repeating` and `vibrato`. Combos are also `stacked` or `sequence`, and jingles `major` or `minor`, `fast` or `slow`, and `harmony` when a second voice plays. Calm apps want soft sounds, playful ones retro. Sounds for frequent actions should be short, so keep jingles for moments that happen once, like finishing a level.

You can't hear them, so pick two or three per event and ask the person you're working with to listen, with `blips play success-003 success-005 success-006` or in the Chip Pops app. Then copy the one they pick into the app, named after what it does there:

```bash
blips export success-003 --to Resources/Sounds --name saved.wav
blips export error-005 --to Resources/Sounds --name failed.wav
```

- Mac and iOS apps: put the WAV files in the target's resources and play them with `NSSound` or `AVAudioPlayer`.
- Web and Electron apps: WAV works in every browser and starts right away. Play it with `new Audio('/sounds/saved.wav').play()`. For sounds longer than half a second, `--format m4a` makes a smaller file, but AAC adds a few milliseconds of silence at the start, so keep WAV for clicks.
- Write down which Chip Pops ID each file came from, in the app's AGENTS.md, so a sound can be swapped later. An ID names a different sound in a library made from another seed, so when `blips show` says the library isn't from seed 1, write the seed down too, and pass it to `export --seed`, which stops if the library doesn't match.
- Play interface sounds quietly (a volume around 0.4), not on every hover, and give people a setting to turn them off.

## The library

- `blips categories` lists the categories and how many sounds each has.
- `blips show <id>` prints the WAV file and the tags. For a single sound it also prints the jsfxr parameters, with a link that opens the sound in sfxr.me to make a variation. For a combo it lists the library sounds it's made of, and for a jingle its notes.
- `blips path <id>` prints a sound's WAV file, and `blips path` the library folder.
- `blips generate` makes the main library again, from seed 1, in about 15 seconds. `--seed random` or another number makes a whole different library. Ask before using it: it replaces every sound in the library.
- `open -a "Chip Pops" --args -select <id>` opens the Chip Pops app on a sound.

## When the command is missing

If `blips` isn't on the PATH, use `"/Applications/Chip Pops.app/Contents/Helpers/blips"`. Chip Pops → Install Command Line Tool links it into `~/.local/bin`. When there's no library yet, `blips generate` makes it.
