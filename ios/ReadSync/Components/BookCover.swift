import SwiftUI

/// An original, generated book cover. No copyrighted artwork — covers are a
/// tasteful gradient + the title/author set in type, like a clean publisher series.
struct BookCover: View {
  let book: Book
  var width: CGFloat = 120
  var showAudioBadge: Bool = true

  private var height: CGFloat { width * 1.5 }

  var body: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(hex: book.coverHexStart), Color(hex: book.coverHexEnd)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      // Faint spine line for a printed feel.
      Rectangle()
        .fill(Color.white.opacity(0.14))
        .frame(width: 2)
        .padding(.leading, width * 0.1)

      VStack(alignment: .leading, spacing: 6) {
        Text(book.title)
          .font(.system(size: width * 0.13, weight: .bold, design: .serif))
          .foregroundStyle(.white)
          .lineLimit(4)
          .minimumScaleFactor(0.7)
        Spacer(minLength: 0)
        Rectangle()
          .fill(Color.white.opacity(0.5))
          .frame(width: width * 0.32, height: 1.5)
        Text(book.author.uppercased())
          .font(.system(size: width * 0.075, weight: .semibold))
          .tracking(0.5)
          .foregroundStyle(.white.opacity(0.85))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .padding(width * 0.12)
      .padding(.leading, width * 0.06)
      // Real cover artwork from the source catalog, layered over the generated
      // gradient so books always show *something* even while the image loads.
      if let url = URL(string: book.coverImageURL), !book.coverImageURL.isEmpty {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image
              .resizable()
              .scaledToFill()
              .transition(.opacity)
          }
        }
        .frame(width: width, height: height)
        .clipped()
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
        .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 6)
    .overlay(alignment: .bottomTrailing) {
      if showAudioBadge && book.hasAudio {
        Image(systemName: "headphones")
          .font(.system(size: width * 0.1, weight: .bold))
          .foregroundStyle(.white)
          .padding(width * 0.06)
          .background(Theme.accent, in: Circle())
          .padding(width * 0.05)
      }
    }
  }
}

/// Small star + number rating row used on detail and discover cards.
struct RatingRow: View {
  let rating: Double
  var size: CGFloat = 12

  var body: some View {
    HStack(spacing: 3) {
      Image(systemName: "star.fill")
        .font(.system(size: size, weight: .semibold))
        .foregroundStyle(Theme.accent)
      Text(String(format: "%.1f", rating))
        .font(.system(size: size + 1, weight: .semibold))
        .foregroundStyle(Theme.inkSoft)
    }
  }
}
