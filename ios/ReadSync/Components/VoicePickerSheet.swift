import SwiftUI

/// A cast-of-narrators picker. Lists every installed English voice grouped by
/// region, lets the user tap to preview, and selects the active narrator. This
/// is the differentiator over a single hardcoded "Rishi" voice.
struct VoicePickerSheet: View {
  @Bindable var narrator: SpeechReader
  @Environment(\.dismiss) private var dismiss

  private let groups = VoiceCatalog.grouped()

  var body: some View {
    NavigationStack {
      Group {
        if groups.isEmpty {
          emptyState
        } else {
          List {
            ForEach(groups, id: \.region) { group in
              Section(group.region) {
                ForEach(group.voices) { voice in
                  row(voice)
                }
              }
            }
          }
          .listStyle(.insetGrouped)
        }
      }
      .navigationTitle("Narrator")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .fontWeight(.semibold)
        }
      }
    }
  }

  private func row(_ voice: NarrationVoice) -> some View {
    let selected = narrator.voice?.id == voice.id
    return Button {
      narrator.selectVoice(voice)
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    } label: {
      HStack(spacing: Theme.md) {
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
        Spacer()
        Button {
          narrator.preview(voice)
        } label: {
          Image(systemName: "play.circle")
            .font(.title3)
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
        if selected {
          Image(systemName: "checkmark.circle.fill")
            .font(.title3)
            .foregroundStyle(Theme.accent)
        }
      }
      .padding(.vertical, 4)
    }
    .buttonStyle(.plain)
  }

  private func avatar(_ voice: NarrationVoice) -> some View {
    let initial = voice.displayName.first.map(String.init) ?? "?"
    return Text(initial)
      .font(.headline.weight(.bold))
      .foregroundStyle(.white)
      .frame(width: 40, height: 40)
      .background(
        LinearGradient(
          colors: [Theme.accent, Theme.accent.opacity(0.6)],
          startPoint: .topLeading, endPoint: .bottomTrailing),
        in: Circle())
  }

  private var emptyState: some View {
    ContentUnavailableView {
      Label("No extra voices yet", systemImage: "waveform")
    } description: {
      Text(
        "Download more narration voices in Settings ▸ Accessibility ▸ Spoken Content ▸ Voices, then they'll appear here."
      )
    }
  }
}
