import SwiftUI

/// Book detail sheet shown from Library/Discover — cover, blurb, rating, and the
/// Read / Listen calls to action plus a "sample" affordance.
struct BookDetailSheet: View {
  let book: Book
  let onRead: () -> Void
  let onListen: () -> Void
  @Environment(\.dismiss) private var dismiss

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
    HStack(spacing: Theme.md) {
      Button(action: onRead) {
        Label(
          book.isStarted ? "Continue" : "Read",
          systemImage: "book.fill"
        )
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
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
  }
}

#Preview {
  BookDetailSheet(book: PreviewData.sampleBook, onRead: {}, onListen: {})
    .modelContainer(PreviewData.container)
}
