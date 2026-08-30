import SwiftUI

/// A cast-of-narrators picker. Lists every installed English voice grouped by
/// region alongside the server-curated ElevenLabs catalogue. Previews are safe
/// public audio URLs; actual premium narration stays routed through Inkflow.
struct VoicePickerSheet: View {
  @Bindable var narrator: SpeechReader
  @Environment(\.dismiss) private var dismiss
  @State private var previewingVoiceID: String?
  @State private var elevenLabsVoices: [ElevenLabsVoice] = []
  @State private var isLoadingElevenLabs = false
  @State private var elevenLabsError: String?

  private let groups = VoiceCatalog.grouped()

  var body: some View {
    NavigationStack {
      List {
        elevenLabsSection

        if !groups.isEmpty {
          ForEach(groups, id: \.region) { group in
            Section("System · \(group.region)") {
              ForEach(group.voices) { voice in
                row(voice)
              }
            }
          }
        } else {
          Section("System voices") { emptyState }
        }
      }
      .listStyle(.insetGrouped)
      .navigationTitle("Narrator")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .top, spacing: 0) {
        Text("Choose a voice for this book. Tap play to hear a short preview.")
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.lg)
          .padding(.vertical, Theme.sm)
          .background(Theme.surfaceAlt.opacity(0.7))
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.semibold)
        }
      }
      .task { await loadElevenLabsVoices() }
    }
  }

  @ViewBuilder
  private var elevenLabsSection: some View {
    Section {
      if isLoadingElevenLabs {
        HStack(spacing: Theme.md) {
          ProgressView()
          Text("Loading available voices…")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
        }
        .padding(.vertical, Theme.sm)
      } else if let elevenLabsError {
        VStack(alignment: .leading, spacing: Theme.sm) {
          Label("Premium voices are unavailable", systemImage: "wifi.exclamationmark")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ink)
          Text(elevenLabsError)
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
          Button("Try again") { Task { await loadElevenLabsVoices() } }
            .font(.caption.weight(.semibold))
            .tint(Theme.accent)
        }
        .padding(.vertical, Theme.xs)
      } else if elevenLabsVoices.isEmpty {
        Text("No premium voices are available for this account right now.")
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
          .padding(.vertical, Theme.xs)
      } else {
        ForEach(elevenLabsVoices) { voice in
          elevenLabsRow(voice)
        }
      }
    } header: {
      HStack(spacing: Theme.xs) {
        Image(systemName: "waveform.badge.sparkles")
        Text("ElevenLabs")
      }
    } footer: {
      Text("Premium narration is generated through Inkflow. System voices always work offline.")
    }
  }

  private func row(_ voice: NarrationVoice) -> some View {
    let selected = narrator.elevenLabsVoice == nil && narrator.voice?.id == voice.id
    return HStack(spacing: Theme.md) {
      Button {
        narrator.selectVoice(voice)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      } label: {
        avatar(voice)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(voice.displayName)
              .font(.body.weight(.semibold))
              .foregroundStyle(Theme.ink)
            if voice.isPremium {
              Text("Premium")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.accent.opacity(0.12), in: Capsule())
            }
          }
          Text(voice.subtitle)
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
        }
        Spacer(minLength: Theme.sm)
      }
      .contentShape(Rectangle())
      .accessibilityLabel("Use \(voice.displayName), \(voice.subtitle)")
      .accessibilityAddTraits(selected ? .isSelected : [])

      Button {
        previewingVoiceID = voice.id
        narrator.preview(voice)
      } label: {
        Image(systemName: previewingVoiceID == voice.id ? "waveform.circle.fill" : "play.circle")
          .font(.title2)
          .foregroundStyle(Theme.accent)
          .frame(width: 40, height: 40)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Preview \(voice.displayName)")

      if selected {
        Image(systemName: "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(Theme.accent)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 4)
    .listRowBackground(selected ? Theme.accent.opacity(0.07) : Color.clear)
  }

  private func elevenLabsRow(_ voice: ElevenLabsVoice) -> some View {
    let selected = narrator.elevenLabsVoice?.id == voice.id
    return HStack(spacing: Theme.md) {
      Button {
        narrator.selectVoice(voice)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
      } label: {
        NarratorGlyph(name: voice.name, tint: Theme.accent)
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(voice.name)
              .font(.body.weight(.semibold))
              .foregroundStyle(Theme.ink)
            Text("ElevenLabs")
              .font(.caption2.weight(.bold))
              .foregroundStyle(Theme.accent)
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(Theme.accent.opacity(0.12), in: Capsule())
          }
          Text(voice.voiceDescription ?? voice.subtitle)
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(2)
        }
        Spacer(minLength: Theme.sm)
      }
      .contentShape(Rectangle())
      .accessibilityLabel("Use ElevenLabs voice \(voice.name), \(voice.subtitle)")
      .accessibilityAddTraits(selected ? .isSelected : [])

      if voice.previewURL != nil {
        Button {
          previewingVoiceID = "elevenlabs-\(voice.id)"
          narrator.preview(voice)
        } label: {
          Image(
            systemName: previewingVoiceID == "elevenlabs-\(voice.id)"
              ? "waveform.circle.fill" : "play.circle")
            .font(.title2)
            .foregroundStyle(Theme.accent)
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Preview ElevenLabs voice \(voice.name)")
      }

      if selected {
        Image(systemName: "checkmark.circle.fill")
          .font(.title3)
          .foregroundStyle(Theme.accent)
          .accessibilityHidden(true)
      }
    }
    .padding(.vertical, 4)
    .listRowBackground(selected ? Theme.accent.opacity(0.07) : Color.clear)
  }

  private func avatar(_ voice: NarrationVoice) -> some View {
    NarratorGlyph(name: voice.displayName, tint: Theme.moss)
  }

  private var emptyState: some View {
    Text("Download natural narration voices in Settings ▸ Accessibility ▸ Spoken Content ▸ Voices.")
      .font(.subheadline)
      .foregroundStyle(Theme.inkSoft)
      .padding(.vertical, Theme.xs)
  }

  @MainActor
  private func loadElevenLabsVoices() async {
    guard !isLoadingElevenLabs else { return }
    isLoadingElevenLabs = true
    elevenLabsError = nil
    defer { isLoadingElevenLabs = false }
    do {
      elevenLabsVoices = try await ElevenLabsCatalogService.loadVoices()
    } catch {
      elevenLabsError = "You can keep listening with system voices and try premium voices again later."
    }
  }
}

/// A deterministic voice-print avatar avoids generic stock portraits while
/// still giving every narrator a distinct, scannable identity.
private struct NarratorGlyph: View {
  let name: String
  let tint: Color

  private var bars: [CGFloat] {
    let scalars = Array(name.unicodeScalars.map(\.value))
    return (0..<5).map { index in
      let value = scalars.isEmpty ? UInt32(index * 7) : scalars[index % scalars.count]
      return CGFloat(9 + Int(value % 16))
    }
  }

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [tint, tint.opacity(0.64)],
            startPoint: .topLeading, endPoint: .bottomTrailing))
      HStack(spacing: 1.8) {
        ForEach(Array(bars.enumerated()), id: \.offset) { _, height in
          Capsule().fill(.white.opacity(0.94)).frame(width: 2.2, height: height)
        }
      }
    }
    .frame(width: 42, height: 42)
    .overlay(Circle().stroke(.white.opacity(0.46), lineWidth: 1))
    .accessibilityHidden(true)
  }
}
