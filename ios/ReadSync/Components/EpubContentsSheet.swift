import SwiftUI

/// Table of contents for an EPUB book — lists spine chapters and jumps to one.
struct EpubContentsSheet: View {
  let chapters: [EpubDocument.Chapter]
  let current: Int
  let theme: ReaderTheme
  let onSelect: (Int) -> Void

  var body: some View {
    NavigationStack {
      List {
        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
          Button {
            onSelect(index)
          } label: {
            HStack(spacing: Theme.md) {
              Text("\(index + 1)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.inkFaint)
                .frame(width: 26, alignment: .trailing)
              Text(chapter.title)
                .font(.subheadline.weight(index == current ? .bold : .regular))
                .foregroundStyle(index == current ? Theme.accent : Theme.ink)
                .lineLimit(2)
              Spacer()
              if index == current {
                Image(systemName: "book.fill")
                  .font(.caption)
                  .foregroundStyle(Theme.accent)
              }
            }
            .padding(.vertical, 2)
          }
        }
      }
      .listStyle(.plain)
      .navigationTitle("Contents")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}
