import Foundation

/// What a sound is like, in a few numbers: its pitch over time, its loudness over time, how tonal
/// it is and how long it is. The generator uses it to keep near copies out of a category.
///
/// It's plain scalar Swift with its own FFT and `ExactMath`, not Accelerate or the system's math
/// library, which can round differently on Intel and Apple silicon: a distance that lands on the
/// other side of the threshold on one of them would give that Mac a different library.
public struct Fingerprint: Sendable, Equatable {
  static let moments = 16
  static let frame = 512

  /// The spectral centroid at each moment, in octaves (log2 of Hz). It follows the pitch, and the
  /// brightness for sounds with many harmonics or noise.
  public let pitch: [Float]
  /// The loudness at each moment, from 0 to 1, where 1 is the loudest moment.
  public let loudness: [Float]
  /// How much of the energy sits in the strongest few frequencies: near 1 for a pure tone, low for noise.
  public let tonality: Float
  /// In seconds.
  public let duration: Float

  public init(_ samples: [Float]) {
    let half = Self.frame / 2
    var pitch = [Float](repeating: .nan, count: Self.moments)
    var loudness = [Float](repeating: 0, count: Self.moments)
    var tonality = [Float](repeating: 0, count: Self.moments)
    var real = [Float](repeating: 0, count: Self.frame)
    var imaginary = [Float](repeating: 0, count: Self.frame)
    var power = [Float](repeating: 0, count: half)

    for moment in 0..<Self.moments {
      let center = (2 * moment + 1) * samples.count / (2 * Self.moments)
      for index in 0..<Self.frame {
        let sample = center - half + index
        real[index] = sample >= 0 && sample < samples.count ? samples[sample] * Self.window[index] : 0
        imaginary[index] = 0
      }
      Self.fft(&real, &imaginary)

      var energy: Float = 0
      var weighted: Float = 0
      for bin in 1..<half {
        power[bin] = real[bin] * real[bin] + imaginary[bin] * imaginary[bin]
        energy += power[bin]
        weighted += Float(bin) * power[bin]
      }
      power[0] = 0
      guard energy > 0 else { continue }
      loudness[moment] = energy.squareRoot()
      pitch[moment] = Float(ExactMath.log2(Double(weighted / energy * Float(WaveFile.sampleRate) / Float(Self.frame))))
      tonality[moment] = power.sorted(by: >).prefix(6).reduce(0, +) / energy
    }

    let loudest = loudness.max() ?? 0
    if loudest > 0 {
      loudness = loudness.map { $0 / loudest }
    }
    // Quiet moments have no pitch worth comparing, so they take the pitch of the moment before.
    let first = zip(pitch, loudness).first { !$0.0.isNaN && $0.1 > 0.02 }?.0 ?? 0
    var previous = first
    for moment in 0..<Self.moments {
      if pitch[moment].isNaN || loudness[moment] <= 0.02 {
        pitch[moment] = previous
      } else {
        previous = pitch[moment]
      }
    }
    let totalLoudness = loudness.reduce(0, +)

    self.pitch = pitch
    self.loudness = loudness
    self.tonality = totalLoudness > 0 ? zip(tonality, loudness).map { $0 * $1 }.reduce(0, +) / totalLoudness : 0
    self.duration = Float(samples.count) / Float(WaveFile.sampleRate)
  }

  /// How different two sounds are. Each part adds about 1 for a big difference: the pitch an octave
  /// apart all along, a completely different loudness shape, a pure tone against noise, or one sound
  /// four times as long as the other.
  public func distance(to other: Fingerprint) -> Float {
    var pitchDifference: Float = 0
    var weight: Float = 0
    var loudnessDifference: Float = 0
    for moment in 0..<Self.moments {
      let louder = max(loudness[moment], other.loudness[moment])
      pitchDifference += louder * abs(pitch[moment] - other.pitch[moment])
      weight += louder
      loudnessDifference += abs(loudness[moment] - other.loudness[moment])
    }
    return pitchDifference / max(weight, 0.000001)
      + loudnessDifference / Float(Self.moments)
      + abs(tonality - other.tonality)
      + 0.5 * Float(abs(ExactMath.log2(Double(duration) / Double(other.duration))))
  }

  private static let window: [Float] = (0..<frame).map {
    Float(0.5 - 0.5 * ExactMath.sinCos(2 * Double.pi * Double($0) / Double(frame)).cos)
  }

  private static let twiddles: (cos: [Float], sin: [Float]) = {
    let angles = (0..<frame / 2).map { ExactMath.sinCos(-2 * Double.pi * Double($0) / Double(frame)) }
    return (angles.map { Float($0.cos) }, angles.map { Float($0.sin) })
  }()

  /// An in-place radix-2 FFT of `frame` points.
  private static func fft(_ real: inout [Float], _ imaginary: inout [Float]) {
    let count = frame
    var j = 0
    for i in 1..<count {
      var bit = count >> 1
      while j & bit != 0 {
        j ^= bit
        bit >>= 1
      }
      j |= bit
      if i < j {
        real.swapAt(i, j)
        imaginary.swapAt(i, j)
      }
    }
    var size = 2
    while size <= count {
      let step = count / size
      for start in stride(from: 0, to: count, by: size) {
        for k in 0..<size / 2 {
          let c = twiddles.cos[k * step]
          let s = twiddles.sin[k * step]
          let a = start + k
          let b = a + size / 2
          let tr = real[b] * c - imaginary[b] * s
          let ti = real[b] * s + imaginary[b] * c
          real[b] = real[a] - tr
          imaginary[b] = imaginary[a] - ti
          real[a] += tr
          imaginary[a] += ti
        }
      }
      size <<= 1
    }
  }
}
