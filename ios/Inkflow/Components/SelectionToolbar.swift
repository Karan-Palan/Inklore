import SwiftUI

/// Floating toolbar shown when a passage is long-pressed — highlight swatches
/// plus note / lookup / share / dismiss, mirroring the Kindle selection menu.
struct SelectionToolbar: View {
  let onHighlight: (HighlightColor) -> Void
  let onNote: () -> Void
  let onLookup: () -> Void
  let onCopy: () -> Void
  let onDismiss: () -> Void
  var shareText: String = "A passage worth sharing from Inkflow."

  var body: some View {
    HStack(spacing: Theme.lg) {
      HStack(spacing: Theme.md) {
        ForEach(HighlightColor.allCases) { color in
          Button {
            onHighlight(color)
          } label: {
            Circle()
              .fill(color.color)
              .frame(width: 26, height: 26)
              .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
          }
          .accessibilityLabel("Highlight in \(color.rawValue)")
        }
      }

      Divider().frame(height: 24)

      Button(action: onLookup) {
        Image(systemName: "character.book.closed")
      }
      .accessibilityLabel("Look up selection")
      Button(action: onNote) {
        Image(systemName: "note.text.badge.plus")
      }
      .accessibilityLabel("Add note")
      Button(action: onCopy) {
        Image(systemName: "doc.on.doc")
      }
      .accessibilityLabel("Copy selection")
      ShareLink(item: shareText) {
        Image(systemName: "square.and.arrow.up")
      }
      .accessibilityLabel("Share selection")
      Button(action: onDismiss) {
        Image(systemName: "xmark")
      }
      .accessibilityLabel("Dismiss selection tools")
    }
    .font(.system(size: 17, weight: .semibold))
    .foregroundStyle(Theme.onControlStrong)
    .padding(.horizontal, Theme.lg)
    .padding(.vertical, Theme.md)
    .background(Theme.controlStrong.opacity(0.98), in: Capsule(style: .continuous))
    .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    .padding(.horizontal, Theme.lg)
    .accessibilityElement(children: .contain)
  }
}

/// Dictionary / Translation / Wikipedia lookup sheet (mock data, no network).
struct LookupSheet: View {
  let term: String
  @State private var tab: Tab = .dictionary

  enum Tab: String, CaseIterable {
    case dictionary = "Dictionary"
    case translation = "Translate"
    case wikipedia = "Wikipedia"
  }

  private var headword: String {
    term.split(separator: " ").prefix(3).joined(separator: " ")
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: Theme.lg) {
        Picker("", selection: $tab) {
          ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)

        ScrollView {
          VStack(alignment: .leading, spacing: Theme.md) {
            switch tab {
            case .dictionary: dictionaryCard
            case .translation: translationCard
            case .wikipedia: wikipediaCard
            }
          }
        }
      }
      .padding(Theme.lg)
      .background(Theme.paper)
      .navigationTitle(headword)
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var dictionaryCard: some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      Text("noun · /ˈnoʊn/")
        .font(.subheadline.italic())
        .foregroundStyle(Theme.inkFaint)
      Text(
        "A passage of text marked by the reader for later recall; a moment held against forgetting."
      )
      .font(.body)
      .foregroundStyle(Theme.ink)
      Text("\"She kept a small archive of borrowed lines.\"")
        .font(.callout.italic())
        .foregroundStyle(Theme.inkSoft)
    }
    .lookupCard()
  }

  private var translationCard: some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      Text("Spanish").font(.caption.weight(.bold)).foregroundStyle(Theme.inkFaint)
      Text("Un pasaje de texto marcado por el lector para recordarlo más tarde.")
        .font(.body).foregroundStyle(Theme.ink)
    }
    .lookupCard()
  }

  private var wikipediaCard: some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      Text("From the reference archive")
        .font(.caption.weight(.bold)).foregroundStyle(Theme.inkFaint)
      Text(
        "Marginalia refers to marks made in the margins of a book or manuscript. Readers have annotated texts for centuries, leaving notes, glosses, and illustrations alongside the printed word."
      )
      .font(.body).foregroundStyle(Theme.ink)
    }
    .lookupCard()
  }
}

extension View {
  fileprivate func lookupCard() -> some View {
    frame(maxWidth: .infinity, alignment: .leading)
      .padding(Theme.lg)
      .background(
        Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
      )
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
          .strokeBorder(Theme.hairline, lineWidth: 1)
      )
  }
}

/// Chapter list / table of contents sheet.
struct TableOfContentsSheet: View {
  let book: Book
  let currentIndex: Int
  let onSelect: (Int) -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
            Button {
              onSelect(index)
            } label: {
              HStack {
                Text(chapter.title)
                  .foregroundStyle(index == currentIndex ? Theme.accent : Theme.ink)
                Spacer()
                if index == currentIndex {
                  Image(systemName: "book.fill")
                    .foregroundStyle(Theme.accent)
                }
              }
            }
          }
        } header: {
          Text(book.title)
        }
      }
      .navigationTitle("Contents")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

/// Action sheet shown when an existing highlight is tapped — recolor, attach or
/// edit a note, copy the passage, or remove the highlight.
struct HighlightActionSheet: View {
  @Bindable var highlight: Highlight
  let existingNote: Note?
  let onChangeColor: (HighlightColor) -> Void
  let onAddOrEditNote: () -> Void
  let onCopy: () -> Void
  let onDelete: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.lg) {
          passage

          colorRow

          if let existingNote, !existingNote.body.isEmpty {
            notePreview(existingNote.body)
          }

          actionRow
        }
        .padding(Theme.lg)
      }
      .background(Theme.paper)
      .navigationTitle("Highlight")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }.tint(Theme.accent)
        }
      }
    }
  }

  private var passage: some View {
    let color = HighlightColor(rawValue: highlight.colorName)?.color ?? Theme.highlightYellow
    return HStack(alignment: .top, spacing: Theme.md) {
      RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 5)
      Text(highlight.text)
        .font(.callout)
        .foregroundStyle(Theme.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var colorRow: some View {
    HStack(spacing: Theme.md) {
      ForEach(HighlightColor.allCases) { color in
        let selected = color.rawValue == highlight.colorName
        Button {
          onChangeColor(color)
        } label: {
          Circle()
            .fill(color.color)
            .frame(width: 34, height: 34)
            .overlay(
              Circle().strokeBorder(selected ? Theme.ink : .white.opacity(0.7), lineWidth: 2.5)
            )
            .overlay {
              if selected {
                Image(systemName: "checkmark")
                  .font(.caption.weight(.bold))
                  .foregroundStyle(Theme.ink)
              }
            }
        }
      }
      Spacer()
    }
  }

  private func notePreview(_ body: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Label("Note", systemImage: "note.text")
        .font(.caption.weight(.bold))
        .foregroundStyle(Theme.inkFaint)
      Text(body).font(.subheadline).foregroundStyle(Theme.inkSoft)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Theme.md)
    .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
  }

  private var actionRow: some View {
    VStack(spacing: Theme.sm) {
      actionButton(
        existingNote == nil ? "Add note" : "Edit note",
        systemImage: "note.text.badge.plus", action: onAddOrEditNote)
      actionButton("Copy passage", systemImage: "doc.on.doc", action: onCopy)
      actionButton(
        "Delete highlight", systemImage: "trash", role: .destructive,
        action: {
          onDelete()
          dismiss()
        })
    }
  }

  private func actionButton(
    _ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void
  ) -> some View {
    Button(role: role, action: action) {
      Label(title, systemImage: systemImage)
        .font(.body.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSm))
        .overlay(
          RoundedRectangle(cornerRadius: Theme.radiusSm).strokeBorder(Theme.hairline))
    }
    .tint(role == .destructive ? .red : Theme.ink)
  }
}

#Preview {
  LookupSheet(term: "marginalia")
}
