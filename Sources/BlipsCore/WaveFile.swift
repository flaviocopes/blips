import Foundation

/// Mono 16-bit PCM WAV files, the format every Chip Pops sound is saved in.
public enum WaveFile {
  public static let sampleRate = 44100

  public static func data(_ samples: [Float]) -> Data {
    var data = Data(capacity: 44 + samples.count * 2)
    func append(_ text: String) { data.append(contentsOf: Array(text.utf8)) }
    func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

    let byteCount = UInt32(samples.count * 2)
    append("RIFF")
    append(36 + byteCount)
    append("WAVE")
    append("fmt ")
    append(UInt32(16))
    append(UInt16(1))  // PCM
    append(UInt16(1))  // mono
    append(UInt32(sampleRate))
    append(UInt32(sampleRate * 2))
    append(UInt16(2))
    append(UInt16(16))
    append("data")
    append(byteCount)
    for sample in samples {
      append(Int16(max(-1, min(1, sample)) * 32767))
    }
    return data
  }

  /// Reads the samples of a mono 8-bit or 16-bit PCM WAV file, on -1...1.
  public static func samples(in data: Data) throws -> [Float] {
    let bytes = [UInt8](data)
    func u32(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24 }
    func u16(_ offset: Int) -> Int { Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 }

    guard bytes.count >= 12, String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF",
      String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE"
    else {
      throw BlipsError("This isn't a WAV file.")
    }
    var bitsPerSample = 16
    var offset = 12
    while offset + 8 <= bytes.count {
      let id = String(decoding: bytes[offset..<offset + 4], as: UTF8.self)
      let size = u32(offset + 4)
      let body = offset + 8
      if id == "fmt " {
        bitsPerSample = u16(body + 14)
      } else if id == "data" {
        let end = min(body + size, bytes.count)
        if bitsPerSample == 8 {
          return bytes[body..<end].map { (Float($0) - 128) / 128 }
        }
        return stride(from: body, to: end - 1, by: 2).map { Float(Int16(bitPattern: UInt16(u16($0)))) / 32768 }
      }
      offset = body + size + size % 2
    }
    throw BlipsError("This WAV file has no samples.")
  }
}

public enum Waveform {
  /// The loudest sample around each of `count` equal slices, for drawing a waveform. Each bar looks at
  /// least `window` samples wide, a full cycle of an 86 Hz tone, so the bars of a short sound follow
  /// its envelope instead of catching each cycle at a different point.
  public static func peaks(_ samples: [Float], count: Int, window: Int = 512) -> [Float] {
    guard count > 0, !samples.isEmpty else { return [] }
    let slice = Double(samples.count) / Double(count)
    let half = max(slice, Double(window)) / 2
    return (0..<count).map { index in
      let center = (Double(index) + 0.5) * slice
      let start = max(0, Int(center - half))
      let end = min(samples.count, max(start + 1, Int(center + half)))
      var peak: Float = 0
      for sample in samples[start..<end] {
        peak = max(peak, abs(sample))
      }
      return peak
    }
  }
}
