import AVKit
import SwiftUI

/// Book detail sheet shown from Library/Discover — cover, blurb, rating, and the
/// Read / Listen calls to action plus a "sample" affordance.
struct BookDetailSheet: View {
  let book: Book
  let onRead: () -> Void
  let onListen: () -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var showingVideoMode = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.xl) {
          VStack(spacing: Theme.md) {
            BookCover(book: book, width: 166)
              .padding(.top, Theme.sm)

            Text(book.category.isEmpty ? "YOUR LIBRARY" : book.category.uppercased())
              .font(.caption2.weight(.heavy))
              .tracking(1.2)
              .foregroundStyle(Theme.accentDeep)
              .padding(.horizontal, Theme.md)
              .padding(.vertical, 6)
              .background(Theme.accentSoft.opacity(0.75), in: Capsule())
          }

          VStack(spacing: 6) {
            Text(book.title)
              .font(.system(.title2, design: .serif).weight(.bold))
              .multilineTextAlignment(.center)
              .foregroundStyle(Theme.ink)
            Text(book.author)
              .font(.subheadline.weight(.semibold))
              .foregroundStyle(Theme.inkSoft)
          }
          .padding(.horizontal, Theme.lg)

          HStack(spacing: Theme.sm) {
            statItem(value: String(format: "%.1f", book.rating), label: "Rating", icon: "star.fill")
            if book.bodyNSLength > 0 {
              statItem(value: "\(estimatedMinutes) min", label: "Read time", icon: "clock")
            }
            if book.canListen {
              statItem(value: "Ready", label: "Audio", icon: "headphones")
            }
          }
          .padding(.horizontal, Theme.lg)

          actionButtons

          VStack(alignment: .leading, spacing: Theme.sm) {
            Text("ABOUT THIS BOOK")
              .font(.caption.weight(.heavy))
              .tracking(1.1)
              .foregroundStyle(Theme.ink)
            Text(book.bookDescription)
              .font(.body)
              .foregroundStyle(Theme.inkSoft)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.lg)
          .padding(.top, Theme.sm)

          if book.isStarted {
            VStack(alignment: .leading, spacing: Theme.sm) {
              HStack {
                Text("YOUR PROGRESS")
                  .font(.caption.weight(.heavy))
                  .tracking(1.1)
                  .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(book.progress * 100))%")
                  .font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
              }
              ThinProgressBar(progress: book.progress)
            }
            .padding(Theme.lg)
            .background(Theme.surfaceAlt.opacity(0.7), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            .padding(.horizontal, Theme.lg)
          }
        }
        .padding(.bottom, Theme.xl)
      }
      .background(Theme.paper)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark.circle.fill")
          }
          .tint(Theme.inkFaint)
        }
      }
      .toolbarBackground(Theme.paper, for: .navigationBar)
      .toolbarBackground(.visible, for: .navigationBar)
      .sheet(isPresented: $showingVideoMode) {
        VideoModeSheet(book: book)
      }
    }
  }

  private var estimatedMinutes: Int {
    // ~200 words/min, ~5.5 chars/word.
    max(1, book.bodyNSLength / Int(5.5 * 200))
  }

  private func statItem(value: String, label: String, icon: String) -> some View {
    VStack(spacing: 5) {
      Label(value, systemImage: icon)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Theme.ink)
      Text(label)
        .font(.caption2)
        .foregroundStyle(Theme.inkFaint)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Theme.md)
    .background(Theme.surfaceAlt.opacity(0.72), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  private var actionButtons: some View {
    VStack(spacing: Theme.sm) {
      HStack(spacing: Theme.md) {
        Button(action: onRead) {
          Label(
            book.isStarted ? "Continue" : "Read",
            systemImage: "book.fill"
          )
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, Theme.md + 1)
          .background(Theme.ink, in: Capsule())
          .foregroundStyle(Theme.paper)
        }
        if book.canListen {
          Button(action: onListen) {
            Label("Listen", systemImage: "headphones")
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, Theme.md + 1)
              .background(Theme.accent, in: Capsule())
              .foregroundStyle(.white)
          }
        }
      }
      if book.bodyNSLength >= 200 {
        Button { showingVideoMode = true } label: {
          Label("Make a chapter video", systemImage: "play.rectangle.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.sm)
        }
        .buttonStyle(.bordered)
        .tint(Theme.accentDeep)
      }
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
  }
}

/// Chapter-specific visual summaries. Jobs survive app dismissal and are
/// polled at a gentle interval; completed scene clips play as one queue.
private struct VideoModeSheet: View {
  let book: Book
  @Environment(\.dismiss) private var dismiss
  @State private var selectedChapterID: String?
  @State private var job: VideoSummaryService.Job?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var player: AVQueuePlayer?
  @State private var pollingTask: Task<Void, Never>?

  private var chapters: [ChapterSummarySection] { ChapterSummaryContent.sections(for: book) }
  private var selectedChapter: ChapterSummarySection? {
    guard let selectedChapterID else { return chapters.first }
    return chapters.first(where: { $0.id == selectedChapterID }) ?? chapters.first
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.lg) {
          Text("Chapter video")
            .font(.system(.title2, design: .serif).weight(.bold))
            .foregroundStyle(Theme.ink)
          Text("Turn one chapter into a short, source-grounded visual recap. The book itself stays in your library.")
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)

          if !chapters.isEmpty {
            Picker("Chapter", selection: $selectedChapterID) {
              ForEach(chapters) { chapter in
                Text(chapter.title).tag(Optional(chapter.id))
              }
            }
            .pickerStyle(.menu)
            .onChange(of: selectedChapterID) { _, _ in
              job = nil
              errorMessage = nil
              player?.pause()
              player = nil
            }
          }

          Group {
            if let player {
              VideoPlayer(player: player)
                .aspectRatio(job?.aspect_ratio == "9:16" ? 9.0 / 16.0 : 16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
            } else {
              videoStatus
            }
          }
          .frame(maxWidth: .infinity)

          if job?.status == "failed" {
            Button("Try this chapter again") { Task { await create() } }
              .buttonStyle(.bordered)
              .tint(Theme.accent)
          } else if job == nil && !isWorking {
            Button("Create video") { Task { await create() } }
              .buttonStyle(.borderedProminent)
              .tint(Theme.accent)
              .disabled(selectedChapter == nil)
          }
        }
        .padding(Theme.lg)
      }
      .background(Theme.paper)
      .navigationTitle(book.title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear { selectedChapterID = chapters.first?.id }
      .onDisappear {
        pollingTask?.cancel()
        player?.pause()
      }
    }
  }

  private var videoStatus: some View {
    VStack(spacing: Theme.md) {
      Image(systemName: job?.status == "failed" ? "exclamationmark.triangle" : "play.rectangle.fill")
        .font(.system(size: 44, weight: .light))
        .foregroundStyle(job?.status == "failed" ? Theme.accent : Theme.ink)
      Text(statusTitle)
        .font(.headline)
        .foregroundStyle(Theme.ink)
      Text(statusDetail)
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.inkSoft)
      if let job, job.total_scenes > 0, job.status != "failed" {
        ProgressView(value: Double(job.completed_scenes), total: Double(job.total_scenes))
          .tint(Theme.accent)
      } else if isWorking {
        ProgressView().tint(Theme.accent)
      }
      if let errorMessage {
        Text(errorMessage)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(Theme.accentDeep)
      }
    }
    .padding(Theme.xl)
    .background(Theme.surfaceAlt.opacity(0.78), in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
  }

  private var statusTitle: String {
    switch job?.status {
    case "planning": return "Writing the visual script"
    case "rendering": return "Rendering scenes"
    case "failed": return job?.provider_status_code == 402 ? "Video access needs an upgrade" : "Generation stopped"
    default: return job == nil ? "A visual recap, chapter by chapter" : "Video queued"
    }
  }

  private var statusDetail: String {
    if job?.provider_status_code == 402 {
      return "ElevenLabs video generation needs a Pro plan or higher. Narration and reading remain available."
    }
    if let job, let duration = job.duration_seconds {
      let orientation = job.aspect_ratio == "9:16" ? "Portrait" : "Landscape"
      return "\(orientation) · about \(duration) seconds · \(job.completed_scenes) of \(job.total_scenes) scenes complete"
    }
    return "Choose a chapter, then Inkflow creates a short video from that chapter’s text."
  }

  @MainActor
  private func create() async {
    guard let selectedChapter else { return }
    isWorking = true
    errorMessage = nil
    player?.pause()
    player = nil
    do {
      job = try await VideoSummaryService.create(book: book, chapter: selectedChapter)
      await pollUntilFinished()
    } catch is CancellationError {
      // The durable backend job continues after a sheet is dismissed.
    } catch {
      errorMessage = error.localizedDescription
    }
    isWorking = false
  }

  @MainActor
  private func pollUntilFinished() async {
    guard let job else { return }
    if job.status == "completed" { preparePlayer(); return }
    if job.status == "failed" { errorMessage = job.error_message; return }
    do {
      try await Task.sleep(for: .seconds(8))
      try Task.checkCancellation()
      self.job = try await VideoSummaryService.status(id: job.id)
      await pollUntilFinished()
    } catch is CancellationError {
      return
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func preparePlayer() {
    let items = job?.scenes.compactMap { scene -> AVPlayerItem? in
      guard let urlString = scene.content_url, let url = URL(string: urlString) else { return nil }
      return AVPlayerItem(url: url)
    } ?? []
    guard !items.isEmpty else {
      errorMessage = "The video finished without playable clips. Please try again."
      return
    }
    let queue = AVQueuePlayer(items: items)
    player = queue
    queue.play()
  }
}

#Preview {
  BookDetailSheet(book: PreviewData.sampleBook, onRead: {}, onListen: {})
    .modelContainer(PreviewData.container)
}
