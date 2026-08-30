import SwiftUI

/// A live, lightweight bar-style waveform that animates while narration plays.
/// Bars react to the narrator's `level` and settle to a calm idle line when
/// paused — a more alive substitute for a static album-art audio screen.
struct AudioWaveform: View {
  var level: Double
  var isPlaying: Bool
  var tint: Color = .white
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let barCount = 32

  var body: some View {
    Group {
      if reduceMotion {
        bars(at: 0)
      } else {
        TimelineView(.animation(minimumInterval: 0.08)) { timeline in
          bars(at: timeline.date.timeIntervalSinceReferenceDate)
        }
      }
    }
    .frame(height: 48)
    .accessibilityHidden(true)
  }

  private func bars(at time: TimeInterval) -> some View {
    HStack(alignment: .center, spacing: 4) {
      ForEach(0..<barCount, id: \.self) { i in
        Capsule()
          .fill(tint.opacity(isPlaying ? 0.88 : 0.42))
          .frame(width: 3, height: barHeight(i, time))
      }
    }
    .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
  }

  private func barHeight(_ index: Int, _ t: Double) -> CGFloat {
    guard isPlaying else { return 3 }
    // Combine a traveling sine wave with the live amplitude for organic motion.
    let phase = Double(index) / Double(barCount) * .pi * 4
    let wave = (sin(t * 6 + phase) + 1) / 2  // 0...1
    let amplitude = max(0.15, level)
    let h = 6 + wave * amplitude * 46
    return CGFloat(h)
  }
}

#Preview {
  ZStack {
    Color.black
    AudioWaveform(level: 0.7, isPlaying: true)
  }
}
