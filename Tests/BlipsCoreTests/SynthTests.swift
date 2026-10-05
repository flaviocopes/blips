import Foundation
import Testing

@testable import BlipsCore

@Suite struct SynthTests {
  @Test func samePresetSeedRollsTheSameParams() throws {
    let synth = try Synth()
    #expect(try synth.preset("pickupCoin", seed: 42) == synth.preset("pickupCoin", seed: 42))
    #expect(try synth.preset("pickupCoin", seed: 42) != synth.preset("pickupCoin", seed: 43))
  }

  @Test func sameSeedRendersTheSameNoise() throws {
    let synth = try Synth()
    let params = try synth.preset("explosion", seed: 7)
    let first = try synth.render(params, seed: 7)
    #expect(first.count > 1000)
    #expect(try synth.render(params, seed: 7) == first)
    #expect(try synth.render(params, seed: 8) != first)
  }

  @Test func paramsKeepJsfxrKeys() throws {
    let synth = try Synth()
    let params = try synth.preset("jump", seed: 1)
    let json = params.json
    #expect(json.contains("\"p_base_freq\""))
    #expect(json.contains("\"wave_type\":0"))
    #expect(try JSONDecoder().decode(SoundParams.self, from: Data(json.utf8)) == params)
  }

  @Test func base58MatchesJsfxr() throws {
    let synth = try Synth()
    let link = try synth.base58(synth.preset("blipSelect", seed: 3))
    #expect(link.count > 50)
    #expect(link.allSatisfy { $0.isLetter || $0.isNumber })
  }

  @Test func unitsMatchJsfxr() {
    #expect(abs(Units.note(0) - 0.35173364) < 0.0001)  // jsfxr's tone preset is 440 Hz
    #expect(abs(Units.arpeggio(ratio: 2) - 0.7454) < 0.001)  // the synth preset's octave up
    #expect(abs(Units.arpeggio(ratio: 0.5) + 0.3162) < 0.001)  // and octave down
    #expect(abs(Units.time(1) - 0.6641) < 0.001)  // the tone preset's one second
  }

  @Test func peaksFollowTheEnvelope() {
    // A 440 Hz tone fading out over 20 ms: every bar should be quieter than the one before.
    let samples = (0..<882).map { Float(sin(Double($0) * 2 * .pi * 440 / 44100) * (1 - Double($0) / 882)) }
    let peaks = Waveform.peaks(samples, count: 40, window: 128)
    #expect(peaks.count == 40)
    #expect(zip(peaks, peaks.dropFirst()).allSatisfy { $0 >= $1 - 0.001 })
  }

  @Test func spectrogramFindsThePitch() {
    // 1 kHz for 50 ms, then 2 kHz: the loudest band of each half should be near that pitch.
    let samples = (0..<4410).map { index in
      Float(sin(Double(index) * 2 * .pi * (index < 2205 ? 1000 : 2000) / 44100))
    }
    let bands = 48
    let columns = Spectrogram.compute(samples, columns: 10, bands: bands)
    #expect(columns.count == 10)
    func loudestPitch(_ column: [Float]) -> Double {
      Spectrogram.frequency(ofBand: column.indices.max { column[$0] < column[$1] }!, of: bands)
    }
    #expect(abs(loudestPitch(columns[1]) / 1000 - 1) < 0.1)
    #expect(abs(loudestPitch(columns[8]) / 2000 - 1) < 0.1)
  }

  @Test func fingerprintsMeasureHowDifferentSoundsAre() {
    func tone(_ hz: Double, seconds: Double) -> [Float] {
      let count = Int(seconds * 44100)
      return (0..<count).map { Float(sin(Double($0) * 2 * .pi * hz / 44100) * (1 - Double($0) / Double(count))) }
    }
    let a440 = Fingerprint(tone(440, seconds: 0.3))
    #expect(a440.distance(to: a440) == 0)
    #expect(abs(a440.distance(to: Fingerprint(tone(880, seconds: 0.3))) - 1) < 0.1)  // an octave up
    #expect(abs(a440.distance(to: Fingerprint(tone(440, seconds: 1.2))) - 1) < 0.1)  // four times as long
    #expect(a440.distance(to: Fingerprint(tone(466, seconds: 0.3))) < LibraryGenerator.threshold)  // a semitone up

    var generator = SeededRandom(seed: 1)
    let noise = (0..<13230).map { _ in Float(generator.range(-1...1)) }
    #expect(a440.tonality > 0.8)
    #expect(Fingerprint(noise).tonality < 0.2)
  }

  @Test func exactMathMatchesTheSystem() {
    var random = SeededRandom(seed: 9)
    for _ in 0..<1000 {
      let x = random.range(-8...8)
      #expect(abs(ExactMath.exp2(x) - pow(2, x)) <= pow(2, x) * 1e-14)
      #expect(abs(ExactMath.sinCos(x).sin - sin(x)) < 1e-13)
      #expect(abs(ExactMath.sinCos(x).cos - cos(x)) < 1e-13)
      let y = random.range(0.001...20000)
      #expect(abs(ExactMath.log2(y) - log2(y)) < 1e-13)
    }
  }

  @Test func waveFileRoundTrips() throws {
    let samples: [Float] = [0, 0.5, -0.5, 1, -1]
    let read = try WaveFile.samples(in: WaveFile.data(samples))
    #expect(read.count == samples.count)
    for (a, b) in zip(read, samples) {
      #expect(abs(a - b) < 0.001)
    }
  }
}
