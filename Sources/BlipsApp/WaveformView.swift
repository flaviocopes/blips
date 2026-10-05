import SwiftUI

/// A waveform as mirrored bars, scaled so the loudest bar fills the height. While the sound plays,
/// the bars after `progress` are dimmed.
struct WaveformView: View {
  let peaks: [Float]
  let color: Color
  var progress: Double? = nil
  var barWidth: CGFloat = 2
  var gap: CGFloat = 1

  var body: some View {
    Canvas { context, size in
      let count = max(1, Int((size.width + gap) / (barWidth + gap)))
      let bars = Self.resample(peaks, to: count)
      let loudest = max(bars.max() ?? 0, 0.0001)
      let middle = size.height / 2
      var played = Path()
      var upcoming = Path()
      for (index, peak) in bars.enumerated() {
        let height = max(barWidth, CGFloat(peak / loudest) * size.height)
        let rect = CGRect(x: CGFloat(index) * (barWidth + gap), y: middle - height / 2, width: barWidth, height: height)
        let bar = Path(roundedRect: rect, cornerRadius: barWidth / 2)
        if let progress, Double(index) / Double(count) > progress {
          upcoming.addPath(bar)
        } else {
          played.addPath(bar)
        }
      }
      context.fill(played, with: .color(color))
      context.fill(upcoming, with: .color(color.opacity(0.3)))
    }
  }

  /// Squeezes or stretches the peaks to `count` bars, keeping the loudest of each group.
  static func resample(_ peaks: [Float], to count: Int) -> [Float] {
    guard !peaks.isEmpty else { return Array(repeating: 0, count: count) }
    return (0..<count).map { index in
      let start = index * peaks.count / count
      let end = max(start + 1, (index + 1) * peaks.count / count)
      return peaks[start..<min(end, peaks.count)].max() ?? 0
    }
  }
}
