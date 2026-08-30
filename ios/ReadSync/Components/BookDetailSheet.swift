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
        VStack(spacing: Theme.lg) {
          BookCover(book: book, width: 168)
            .padding(.top, Theme.lg)

          VStack(spacing: 6) {
            Text(book.title)
              .font(.title2.weight(.bold))
              .multilineTextAlignment(.center)
              .foregroundStyle(Theme.ink)
            Text(book.author)
              .font(.headline)
              .foregroundStyle(Theme.inkSoft)
          }
          .padding(.horizontal, Theme.lg)

          HStack(spacing: Theme.xl) {
            statItem(value: String(format: "%.1f", book.rating), label: "Rating", icon: "star.fill")
            if book.bodyNSLength > 0 {
              statItem(value: "\(estimatedMinutes) min", label: "Read time", icon: "clock")
            }
            if book.canListen {
              statItem(value: "Audio", label: "Listen", icon: "headphones")
            }
          }

          actionButtons

          VStack(alignment: .leading, spacing: Theme.sm) {
            Text("About this book")
              .font(.headline)
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
                Text("Your progress").font(.headline).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(book.progress * 100))%")
                  .font(.subheadline.weight(.bold)).foregroundStyle(Theme.accent)
              }
              ThinProgressBar(progress: book.progress)
            }
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
    VStack(spacing: 4) {
      Label(value, systemImage: icon)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Theme.ink)
      Text(label)
        .font(.caption2)
        .foregroundStyle(Theme.inkFaint)
    }
  }

  private var actionButtons: some View {
    VStack(spacing: Theme.sm) {
      HStack(spacing: Theme.md) {
        Button(action: onRead) {
          Label(book.isStarted ? "Continue" : "Read", systemImage: "book.fill")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.md)
            .background(Theme.ink, in: Capsule())
            .foregroundStyle(Theme.paper)
        }
        if book.canListen {
          Button(action: onListen) {
            Label("Listen", systemImage: "headphones")
              .font(.headline)
              .frame(maxWidth: .infinity)
              .padding(.vertical, Theme.md)
              .background(Theme.accent, in: Capsule())
              .foregroundStyle(.white)
          }
        }
      }
      if book.bodyNSLength > 0 {
        Button { showingVideoMode = true } label: {
          Label("Create video mode", systemImage: "play.rectangle.fill")
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.sm)
        }
        .buttonStyle(.bordered)
        .clipShape(Capsule())
      }
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
  }
}

#Preview {
  BookDetailSheet(book: PreviewData.sampleBook, onRead: {}, onListen: {})
    .modelContainer(PreviewData.container)
    .environment(AuthStore())
}

private struct VideoModeSheet: View {
  let book: Book
  @Environment(AuthStore.self) private var auth
  @Environment(\.dismiss) private var dismiss
  @State private var job: VideoSummaryService.Job?
  @State private var isWorking = false
  @State private var errorMessage: String?
  @State private var player: AVQueuePlayer?

  var body: some View {
    NavigationStack {
      VStack(spacing: Theme.lg) {
        if let player {
          VideoPlayer(player: player)
            .aspectRatio(
              job?.aspect_ratio == "9:16" ? CGFloat(9.0 / 16.0) : CGFloat(16.0 / 9.0),
              contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        } else {
          Image(systemName: "play.rectangle.fill")
            .font(.system(size: 52)).foregroundStyle(Theme.accent)
          Text(statusTitle).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
          Text(statusDetail)
            .font(.subheadline).foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
          if let job, job.total_scenes > 0 {
            ProgressView(value: Double(job.completed_scenes), total: Double(job.total_scenes))
          } else if isWorking {
            ProgressView()
          }
          if let errorMessage {
            Text(errorMessage).font(.footnote).foregroundStyle(.red)
          }
          if job == nil && !isWorking {
            Button("Create video") { Task { await create() } }
              .buttonStyle(.borderedProminent).tint(Theme.accent)
              .disabled(!auth.isSignedIn)
          }
        }
        Spacer()
      }
      .padding(Theme.lg)
      .background(Theme.paper)
      .navigationTitle("Video mode")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
      }
    }
  }

  private var statusTitle: String {
    guard auth.isSignedIn else { return "Sign in to create a video" }
    switch job?.status {
    case "planning": return "Writing the visual script"
    case "rendering": return "Rendering scenes"
    case "failed": return "Generation stopped"
    default: return job == nil ? "Turn this book into a video" : "Video queued"
    }
  }

  private var statusDetail: String {
    if let job, let duration = job.duration_seconds {
      return "\(job.aspect_ratio ?? "") · about \(duration) seconds · \(job.completed_scenes)/\(job.total_scenes) scenes"
    }
    return "The script chooses portrait or landscape and a length that fits the book."
  }

  @MainActor
  private func create() async {
    isWorking = true
    errorMessage = nil
    guard let token = await auth.validAccessToken() else {
      errorMessage = "Please sign in first."
      isWorking = false
      return
    }
    do {
      job = try await VideoSummaryService.create(book: book, accessToken: token)
      while let current = job, !["completed", "failed"].contains(current.status) {
        try await Task.sleep(for: .seconds(4))
        try Task.checkCancellation()
        job = try await VideoSummaryService.status(id: current.id, accessToken: token)
      }
      if job?.status == "completed" {
        let items = job?.scenes.compactMap { scene -> AVPlayerItem? in
          guard let value = scene.content_url, let url = URL(string: value) else { return nil }
          return AVPlayerItem(url: url)
        } ?? []
        if !items.isEmpty {
          player = AVQueuePlayer(items: items)
          player?.play()
        }
      } else {
        errorMessage = job?.error_message ?? "The video could not be generated."
      }
    } catch is CancellationError {
      // Closing the sheet cancels polling without cancelling the durable job.
    } catch {
      errorMessage = error.localizedDescription
    }
    isWorking = false
  }
}
