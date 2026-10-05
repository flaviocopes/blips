import Foundation

/// jsfxr's sound parameters, encoded with jsfxr's own JSON keys, so a sound pastes unchanged
/// into https://sfxr.me or into `sfxr.toAudio()` in a web app. Most are on 0...1, the ones
/// jsfxr calls signed are on -1...1.
public struct SoundParams: Codable, Hashable, Sendable {
  public enum Wave: Int, Codable, Sendable, CaseIterable {
    case square, sawtooth, sine, noise

    public var name: String {
      switch self {
      case .square: "square"
      case .sawtooth: "sawtooth"
      case .sine: "sine"
      case .noise: "noise"
      }
    }
  }

  public var wave: Wave = .square
  public var attack = 0.0
  public var sustain = 0.3
  public var punch = 0.0
  public var decay = 0.4
  public var baseFrequency = 0.3
  public var frequencyLimit = 0.0
  public var frequencySlide = 0.0
  public var frequencyDeltaSlide = 0.0
  public var vibratoDepth = 0.0
  public var vibratoSpeed = 0.0
  public var arpeggioChange = 0.0
  public var arpeggioSpeed = 0.0
  public var duty = 0.0
  public var dutySweep = 0.0
  public var repeatSpeed = 0.0
  public var flangerOffset = 0.0
  public var flangerSweep = 0.0
  public var lowPassCutoff = 1.0
  public var lowPassSweep = 0.0
  public var lowPassResonance = 0.0
  public var highPassCutoff = 0.0
  public var highPassSweep = 0.0
  public var volume = 0.25
  public var sampleRate = 44100
  public var sampleSize = 8

  public init() {}

  enum CodingKeys: String, CodingKey {
    case wave = "wave_type"
    case attack = "p_env_attack"
    case sustain = "p_env_sustain"
    case punch = "p_env_punch"
    case decay = "p_env_decay"
    case baseFrequency = "p_base_freq"
    case frequencyLimit = "p_freq_limit"
    case frequencySlide = "p_freq_ramp"
    case frequencyDeltaSlide = "p_freq_dramp"
    case vibratoDepth = "p_vib_strength"
    case vibratoSpeed = "p_vib_speed"
    case arpeggioChange = "p_arp_mod"
    case arpeggioSpeed = "p_arp_speed"
    case duty = "p_duty"
    case dutySweep = "p_duty_ramp"
    case repeatSpeed = "p_repeat_speed"
    case flangerOffset = "p_pha_offset"
    case flangerSweep = "p_pha_ramp"
    case lowPassCutoff = "p_lpf_freq"
    case lowPassSweep = "p_lpf_ramp"
    case lowPassResonance = "p_lpf_resonance"
    case highPassCutoff = "p_hpf_freq"
    case highPassSweep = "p_hpf_ramp"
    case volume = "sound_vol"
    case sampleRate = "sample_rate"
    case sampleSize = "sample_size"
  }

  /// The pitch the sound starts at, in Hz.
  public var startFrequency: Double {
    8 * 44100 * (baseFrequency * baseFrequency + 0.001) / 100
  }

  /// The note nearest to the starting pitch, like C5.
  public var noteName: String {
    let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
    let midi = Int((69 + 12 * log2(startFrequency / 440)).rounded())
    return names[((midi % 12) + 12) % 12] + String(midi / 12 - 1)
  }

  /// How long the note is held before it fades, in seconds: the attack and the sustain.
  public var heldLength: Double {
    (attack * attack + sustain * sustain) / 0.441
  }

  public var json: String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
  }
}

/// Converts between jsfxr's 0...1 slider values and real units, so recipes read in seconds and Hz.
/// The formulas are the ones in jsfxr's `SoundEffect.init`.
enum Units {
  /// The base frequency for a pitch in Hz.
  static func frequency(hz: Double) -> Double {
    max(hz / 3528 - 0.001, 0).squareRoot()
  }

  /// The pitch of a note, in semitones from A4 (440 Hz).
  static func note(_ semitones: Double) -> Double {
    frequency(hz: 440 * ExactMath.exp2(semitones / 12))
  }

  /// An attack, sustain or decay time.
  static func time(_ seconds: Double) -> Double {
    (seconds * 0.441).squareRoot()
  }

  /// The arpeggio change that multiplies the pitch by `ratio`: above 1 jumps up, below 1 jumps down.
  static func arpeggio(ratio: Double) -> Double {
    ratio >= 1 ? ((1 - 1 / ratio) / 0.9).squareRoot() : -((1 / ratio - 1) / 10).squareRoot()
  }

  /// The arpeggio or repeat speed that acts after `seconds`.
  static func delay(_ seconds: Double) -> Double {
    1 - (max(seconds * 44100 - 32, 0) / 20000).squareRoot()
  }
}
