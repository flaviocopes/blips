import Foundation

/// Pitch over time, for drawing what a sound does: the jump of an arpeggio, a slide, vibrato, noise.
/// The bands are spaced like musical notes, so an octave is as tall at 200 Hz as at 4 kHz.
public enum Spectrogram {
  public static let lowest = 80.0
  public static let highest = 12000.0
  static let floor = 60.0

  /// How loud each of `bands` pitches from `lowest` to `highest` Hz is at each of `columns` moments,
  /// on 0...1: 1 is the loudest point of the sound, 0 is 60 dB quieter or less. Each column lists
  /// its bands from low to high. Every band is measured with the Goertzel algorithm over a
  /// `frame`-sample Hann window.
  public static func compute(_ samples: [Float], columns: Int, bands: Int, frame: Int = 1024) -> [[Float]] {
    guard columns > 0, bands > 1, !samples.isEmpty else { return [] }
    let window = (0..<frame).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(frame - 1)) }
    let coefficients = (0..<bands).map { band in
      2 * cos(2 * Double.pi * frequency(ofBand: band, of: bands) / Double(WaveFile.sampleRate))
    }

    var windowed = [Double](repeating: 0, count: frame)
    let powers = (0..<columns).map { column -> [Double] in
      let center = (Double(column) + 0.5) * Double(samples.count) / Double(columns)
      let start = Int(center) - frame / 2
      for index in 0..<frame {
        let sample = start + index
        windowed[index] = sample >= 0 && sample < samples.count ? Double(samples[sample]) * window[index] : 0
      }
      return coefficients.map { coefficient in
        var previous = 0.0
        var beforePrevious = 0.0
        for value in windowed {
          let current = value + coefficient * previous - beforePrevious
          beforePrevious = previous
          previous = current
        }
        return previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious
      }
    }

    let loudest = max(powers.lazy.flatMap { $0 }.max() ?? 0, 1e-20)
    return powers.map { column in
      column.map { power in Float(max(0, 1 + 10 * log10(max(power, 1e-20) / loudest) / floor)) }
    }
  }

  /// The pitch at the middle of a band, in Hz.
  public static func frequency(ofBand band: Int, of bands: Int) -> Double {
    lowest * pow(highest / lowest, Double(band) / Double(bands - 1))
  }
}
