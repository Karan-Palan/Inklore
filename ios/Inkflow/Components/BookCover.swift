import SwiftUI

/// A polished catalog cover with a typographic fallback. Remote artwork is used
/// when a source provides it; the fallback keeps imported files feeling cared for.
struct BookCover: View {
  let book: Book
  var width: CGFloat = 120
  var showAudioBadge: Bool = true

  private var height: CGFloat { width * 1.5 }

  var body: some View {
    ZStack(alignment: .topLeading) {
      fallbackCover

      // A source cover takes visual priority, while the custom fallback remains
      // visible immediately for imports and slow connections.
      if let url = URL(string: book.coverImageURL), !book.coverImageURL.isEmpty {
        AsyncImage(url: url) { phase in
          if case .success(let image) = phase {
            image
              .resizable()
              .scaledToFill()
              .transition(.opacity)
          } else if case .empty = phase {
            Rectangle()
              .fill(Color.white.opacity(0.001))
          }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
      }
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
        .strokeBorder(Color.black.opacity(0.1), lineWidth: 0.6)
    )
    .shadow(color: Theme.shadow.opacity(0.7), radius: 10, x: 0, y: 7)
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(book.title) by \(book.author)\(book.hasAudio ? ", with audio" : "")")
  }

  private var fallbackCover: some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: Theme.radiusSm, style: .continuous)
        .fill(
          LinearGradient(
            colors: [Color(hex: book.coverHexStart), Color(hex: book.coverHexEnd)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )

      Circle()
        .fill(.white.opacity(0.13))
        .frame(width: width * 0.82, height: width * 0.82)
        .offset(x: width * 0.42, y: -width * 0.3)
      Capsule()
        .fill(.white.opacity(0.14))
        .frame(width: width * 0.09, height: height * 0.63)
        .padding(.leading, width * 0.11)
        .padding(.top, height * 0.15)

      VStack(alignment: .leading, spacing: max(4, width * 0.045)) {
        Text("INKFLOW EDITION")
          .font(.system(size: max(5, width * 0.052), weight: .black))
          .tracking(width * 0.008)
          .foregroundStyle(.white.opacity(0.74))
          .lineLimit(1)
        Spacer(minLength: width * 0.14)
        Text(book.title)
          .font(.system(size: width * 0.135, weight: .bold, design: .serif))
          .foregroundStyle(.white)
          .lineLimit(4)
          .minimumScaleFactor(0.62)
        Spacer(minLength: 0)
        Rectangle()
          .fill(.white.opacity(0.62))
          .frame(width: width * 0.36, height: max(1, width * 0.012))
        Text(book.author.uppercased())
          .font(.system(size: max(6, width * 0.07), weight: .bold))
          .tracking(width * 0.006)
          .foregroundStyle(.white.opacity(0.86))
          .lineLimit(1)
          .minimumScaleFactor(0.65)
      }
      .padding(width * 0.12)
      .padding(.leading, width * 0.075)
    }
    .frame(width: width, height: height)
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
