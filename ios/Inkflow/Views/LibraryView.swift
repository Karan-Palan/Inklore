import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.appRouter) private var router
  @Query(sort: \Book.title) private var books: [Book]

  @State private var searchText = ""
  @State private var selectedCategory = "All"
  @State private var readerBook: Book?
  @State private var playerBook: Book?
  @State private var detailBook: Book?
  @State private var showImporter = false
  @State private var showBackups = false
  @State private var showURLImport = false
  @State private var showTextImport = false
  @State private var importURLText = ""
  @State private var isImporting = false
  @State private var importError: String?
  @FocusState private var searchFocused: Bool

  private var continueReading: [Book] {
    books
      .filter { $0.isStarted && !$0.isFinished }
      .sorted { ($0.lastOpenedDate ?? .distantPast) > ($1.lastOpenedDate ?? .distantPast) }
  }

  private var primaryBook: Book? { continueReading.first }

  private var searchResults: [Book] {
    guard !searchText.isEmpty else { return [] }
    return books.filter {
      $0.title.localizedCaseInsensitiveContains(searchText)
        || $0.author.localizedCaseInsensitiveContains(searchText)
    }
  }

  /// Real category pills derived from the books the user actually has, with
  /// "All" pinned first. No static genre list.
  private var libraryCategories: [String] {
    let cats = Set(books.map(\.category).filter { !$0.isEmpty })
    return ["All"] + cats.sorted()
  }

  private var filteredBooks: [Book] {
    selectedCategory == "All"
      ? books
      : books.filter { $0.category == selectedCategory }
  }

  private var recentAdditions: [Book] {
    filteredBooks.sorted { $0.addedDate > $1.addedDate }
  }

  private var audiobooks: [Book] {
    filteredBooks.filter { $0.canListen && $0.hasAudio }
  }

  private var supportedImportTypes: [UTType] {
    var types: [UTType] = [.pdf, .epub, .plainText, .rtf, .html]
    for fileExtension in ["docx", "md", "markdown"] {
      if let type = UTType(filenameExtension: fileExtension), !types.contains(type) {
        types.append(type)
      }
    }
    return types
  }

  var body: some View {
    Group {
      NavigationStack {
        VStack(spacing: 0) {
          ScreenHeader("Library") {
            Menu {
              Button {
                showImporter = true
              } label: {
                Label("Import from Files", systemImage: "folder")
              }
              Button {
                importURLText = ""
                showURLImport = true
              } label: {
                Label("Add from link", systemImage: "link")
              }
              Button {
                showTextImport = true
              } label: {
                Label("Paste text", systemImage: "doc.on.clipboard")
              }
              Divider()
              Button {
                router.openSearch(query: "")
              } label: {
                Label("Find free books", systemImage: "globe")
              }
              Button {
                showBackups = true
              } label: {
                Label("Cloud Backups", systemImage: "icloud.and.arrow.up")
              }
            } label: {
              Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 32, height: 32)
            }
          }
          InlineSearchField(
            prompt: "Find a title or author", text: $searchText, focused: $searchFocused)
          ScrollView {
            if !searchText.isEmpty {
              searchResultsSection
            } else if books.isEmpty {
              emptyLibrary
            } else {
              VStack(alignment: .leading, spacing: Theme.xl) {
                libraryWelcome
                if let primaryBook {
                  continueHero(primaryBook)
                } else {
                  libraryStarter
                }
                if continueReading.count > 1 {
                  shelf("Continue reading", books: Array(continueReading.dropFirst()))
                }
                if libraryCategories.count > 1 {
                  CategoryFilterBar(categories: libraryCategories, selection: $selectedCategory)
                }
                shelf("Recently added", books: recentAdditions)
                if selectedCategory == "All", !audiobooks.isEmpty {
                  shelf("Listening next", books: audiobooks)
                }
                Color.clear.frame(height: Theme.lg)
              }
              .padding(.top, Theme.sm)
            }
          }
        }
        .background(Theme.paper)
        .fileImporter(
          isPresented: $showImporter,
          allowedContentTypes: supportedImportTypes,
          allowsMultipleSelection: true
        ) { result in
          handleFileImport(result)
        }
        .alert("Import from link", isPresented: $showURLImport) {
          TextField("https://example.com/book.pdf", text: $importURLText)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Cancel", role: .cancel) {}
          Button("Import") { handleURLImport() }
        } message: {
          Text("Paste any public article, Paul Graham or X post, or a link to a PDF, EPUB, DOCX, RTF, Markdown, or text file.")
        }
        .alert(
          "Import failed", isPresented: .constant(importError != nil), presenting: importError
        ) { _ in
          Button("OK", role: .cancel) { importError = nil }
        } message: { message in
          Text(message)
        }
        .overlay {
          if isImporting {
            ZStack {
              Color.black.opacity(0.2).ignoresSafeArea()
              ProgressView("Importing…")
                .padding(Theme.lg)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.radiusLg))
            }
          }
        }
        .fullScreenCover(item: $readerBook) { book in
          BookReader(book: book)
        }
        .fullScreenCover(item: $playerBook) { book in
          PlayerView(book: book)
        }
        .sheet(item: $detailBook) { book in
          BookDetailSheet(
            book: book, onRead: { startReading(book) }, onListen: { playerBook = book })
        }
        .sheet(isPresented: $showBackups) {
          BackupsView()
        }
        .sheet(isPresented: $showTextImport) {
          PasteTextImportSheet { title, text in
            handleTextImport(title: title, text: text)
          }
        }
      }
    }
    .__tenxTrackView("LibraryView")
  }

  // MARK: Empty state

  private var emptyLibrary: some View {
    let genre = OnboardingFlag.selectedGenre
    return VStack(spacing: Theme.xl) {
      ZStack {
        Circle()
          .fill(Theme.mossSoft.opacity(0.76))
          .frame(width: 126, height: 126)
        Image(systemName: "books.vertical.fill")
          .font(.system(size: 48, weight: .medium))
          .foregroundStyle(Theme.moss)
        Image(systemName: "sparkle")
          .font(.title3.weight(.bold))
          .foregroundStyle(Theme.accent)
          .offset(x: 40, y: -38)
      }
      .accessibilityHidden(true)

      VStack(spacing: Theme.sm) {
        Text("Your next chapter starts here")
          .font(.system(.title2, design: .serif).weight(.bold))
          .foregroundStyle(Theme.ink)
        Text(
          "Choose a free \(genre.name.lowercased()) pick, or bring a book already waiting for you."
        )
        .font(.subheadline.weight(.medium))
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, Theme.lg)
      }

      // Real covers of the reader's genre, tapping straight into a Search.
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: Theme.md) {
          ForEach(genre.recommendations(4)) { rec in
            Button {
              router.openSearch(query: rec.searchQuery)
            } label: {
              VStack(spacing: 6) {
                GenreCoverThumb(url: rec.coverURL, tint: genre.tint, width: 92)
                Text(rec.title)
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(2)
                  .multilineTextAlignment(.center)
                  .frame(width: 92)
              }
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, Theme.lg)
      }
      .padding(.top, Theme.sm)

      HStack(spacing: Theme.sm) {
        Button {
          router.openSearch(query: "\(genre.name)")
        } label: {
          Label("Find a book", systemImage: "magnifyingglass")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.paper)
            .padding(.horizontal, Theme.lg)
            .padding(.vertical, Theme.sm + 5)
            .background(Theme.ink, in: Capsule())
        }

        Button {
          showImporter = true
        } label: {
          Image(systemName: "square.and.arrow.down")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.ink)
            .frame(width: 42, height: 42)
            .background(Theme.surface, in: Circle())
            .overlay(Circle().stroke(Theme.hairline, lineWidth: 1))
        }
        .accessibilityLabel("Import a book from Files")
      }

      Text("You can also import a PDF, EPUB, Word document, article, or your own text.")
        .font(.footnote)
        .foregroundStyle(Theme.inkFaint)
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.xl)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 46)
    .padding(.horizontal, Theme.lg)
  }

  // MARK: Continue hero

  private var libraryWelcome: some View {
    HStack(alignment: .firstTextBaseline, spacing: Theme.md) {
      VStack(alignment: .leading, spacing: 4) {
        Text("YOUR SHELF")
          .font(.caption2.weight(.heavy))
          .tracking(1.2)
          .foregroundStyle(Theme.inkFaint)
        Text(books.count == 1 ? "One story, ready whenever you are." : "\(books.count) stories, all in one calm place.")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.ink)
      }
      Spacer(minLength: 0)
      Image(systemName: "leaf.fill")
        .font(.title3.weight(.semibold))
        .foregroundStyle(Theme.moss)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.md)
  }

  private var libraryStarter: some View {
    HStack(spacing: Theme.md) {
      Image(systemName: "book.closed.fill")
        .font(.title3)
        .foregroundStyle(Theme.accentDeep)
        .frame(width: 46, height: 46)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
      VStack(alignment: .leading, spacing: 3) {
        Text("Pick up where curiosity leads")
          .font(.subheadline.weight(.bold))
          .foregroundStyle(Theme.ink)
        Text("Choose a recent title below to begin your next session.")
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
      }
      Spacer(minLength: 0)
    }
    .padding(Theme.md)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
        .stroke(Theme.hairline, lineWidth: 1)
    }
    .padding(.horizontal, Theme.lg)
  }

  private func continueHero(_ book: Book) -> some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      Text("CONTINUE READING")
        .font(.caption2.weight(.heavy))
        .tracking(1.2)
        .foregroundStyle(Theme.inkFaint)
        .padding(.horizontal, Theme.lg)

      HStack(alignment: .top, spacing: Theme.lg) {
        BookCover(book: book, width: 110)
          .onTapGesture { startReading(book) }

        VStack(alignment: .leading, spacing: Theme.sm) {
          Text(book.title)
            .font(.system(.title3, design: .serif).weight(.bold))
            .foregroundStyle(Theme.ink)
            .lineLimit(2)
          Text(book.author)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.inkSoft)

          Spacer(minLength: Theme.sm)

          HStack(spacing: 6) {
            Text("\(Int(book.progress * 100))%")
              .font(.subheadline.weight(.bold))
              .foregroundStyle(Theme.accent)
            Text("· page \(book.currentPage) of \(book.totalPages)")
              .font(.caption)
              .foregroundStyle(Theme.inkFaint)
          }
          ThinProgressBar(progress: book.progress)

          HStack(spacing: Theme.sm) {
            Button {
              startReading(book)
            } label: {
              Label("Read", systemImage: "book.fill")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.ink, in: Capsule())
                .foregroundStyle(Theme.paper)
            }
            if book.hasAudio {
              Button {
                playerBook = book
              } label: {
                Image(systemName: "headphones")
                  .font(.subheadline.weight(.semibold))
                  .padding(.vertical, 10)
                  .padding(.horizontal, Theme.lg)
                  .background(Theme.surfaceAlt, in: Capsule())
                  .foregroundStyle(Theme.ink)
              }
            }
          }
          .padding(.top, Theme.xs)
        }
      }
      .padding(Theme.lg)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
          .strokeBorder(Theme.hairline, lineWidth: 1)
      )
      .shadow(color: Theme.shadow.opacity(0.3), radius: 14, y: 6)
      .padding(.horizontal, Theme.lg)
    }
  }

  // MARK: Shelf

  private func shelf(_ title: String, books: [Book]) -> some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      SectionHeader(title: title)
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: Theme.md) {
          ForEach(books) { book in
            Button {
              detailBook = book
            } label: {
              VStack(alignment: .leading, spacing: 7) {
                BookCover(book: book, width: 116)
                if book.isStarted && !book.isFinished {
                  ThinProgressBar(progress: book.progress)
                    .frame(width: 116)
                  Text("\(Int(book.progress * 100))% complete")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkFaint)
                } else if book.isFinished {
                  Label("Finished", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.moss)
                } else if book.hasAudio {
                  Label("Read or listen", systemImage: "headphones")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.accentDeep)
                } else {
                  Text("Ready to read")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.inkFaint)
                }
              }
              .frame(width: 116, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open \(book.title) by \(book.author)")
          }
        }
        .padding(.horizontal, Theme.lg)
      }
    }
  }

  // MARK: Search results

  private var searchResultsSection: some View {
    LazyVStack(spacing: 0) {
      if searchResults.isEmpty {
        ContentUnavailableView.search(text: searchText)
          .padding(.top, 80)
      } else {
        ForEach(searchResults) { book in
          Button {
            detailBook = book
          } label: {
            BookRow(book: book)
          }
          .buttonStyle(.plain)
          Divider().padding(.leading, 96)
        }
      }
    }
    .padding(.top, Theme.sm)
  }

  private func startReading(_ book: Book) {
    detailBook = nil
    book.lastOpenedDate = .now
    readerBook = book
  }

  // MARK: Import

  private func handleFileImport(_ result: Result<[URL], Error>) {
    switch result {
    case .success(let urls):
      guard !urls.isEmpty else { return }
      isImporting = true
      Task { @MainActor in
        var failures = 0
        for url in urls {
          do {
            try await BookImporter.importFile(at: url, into: context)
          } catch {
            failures += 1
            importError =
              (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          }
        }
        isImporting = false
        if failures == 0 {
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
      }
    case .failure(let error):
      importError = error.localizedDescription
    }
  }

  private func handleURLImport() {
    let trimmed = importURLText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
      importError = "That doesn't look like a valid link."
      return
    }
    isImporting = true
    Task { @MainActor in
      do {
        try await BookImporter.importLink(from: url, into: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
      isImporting = false
    }
  }

  private func handleTextImport(title: String, text: String) {
    Task { @MainActor in
      do {
        try await BookImporter.importText(title: title, text: text, into: context)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
      } catch {
        importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      }
    }
  }
}

private struct PasteTextImportSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var title = ""
  @State private var text = ""
  @FocusState private var bodyFocused: Bool
  let onImport: (String, String) -> Void

  private var canImport: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.lg) {
          VStack(alignment: .leading, spacing: Theme.sm) {
            Image(systemName: "text.quote")
              .font(.system(size: 30, weight: .semibold))
              .foregroundStyle(Theme.accent)
            Text("Turn any text into a book")
              .font(.title2.bold())
              .foregroundStyle(Theme.ink)
            Text("Paste notes, an essay, or a draft. Inkflow will make it readable, highlightable, and listenable.")
              .font(.subheadline)
              .foregroundStyle(Theme.inkSoft)
          }

          VStack(alignment: .leading, spacing: Theme.sm) {
            Text("TITLE")
              .font(.caption2.bold())
              .tracking(1.2)
              .foregroundStyle(Theme.inkFaint)
            TextField("Untitled reading", text: $title)
              .font(.body.weight(.medium))
              .padding(Theme.md)
              .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
          }

          VStack(alignment: .leading, spacing: Theme.sm) {
            HStack {
              Text("TEXT")
                .font(.caption2.bold())
                .tracking(1.2)
                .foregroundStyle(Theme.inkFaint)
              Spacer()
              Text("\(text.split(whereSeparator: \.isWhitespace).count) words")
                .font(.caption)
                .foregroundStyle(Theme.inkFaint)
            }
            TextEditor(text: $text)
              .focused($bodyFocused)
              .font(.body)
              .scrollContentBackground(.hidden)
              .padding(Theme.sm)
              .frame(minHeight: 260, alignment: .top)
              .background(Theme.surfaceAlt, in: RoundedRectangle(cornerRadius: Theme.radiusMd))
              .overlay(alignment: .topLeading) {
                if text.isEmpty {
                  Text("Paste or type here…")
                    .font(.body)
                    .foregroundStyle(Theme.inkFaint)
                    .padding(.horizontal, Theme.md + 1)
                    .padding(.vertical, Theme.md + 7)
                    .allowsHitTesting(false)
                }
              }
          }
        }
        .padding(Theme.lg)
      }
      .background(Theme.paper)
      .navigationTitle("Paste text")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Add to library") {
            onImport(title, text)
            dismiss()
          }
          .fontWeight(.semibold)
          .disabled(!canImport)
        }
      }
      .onAppear { bodyFocused = true }
    }
    .presentationDetents([.large])
  }
}

/// Horizontal list row used in search results.
struct BookRow: View {
  let book: Book

  var body: some View {
    HStack(spacing: Theme.md) {
      BookCover(book: book, width: 60, showAudioBadge: false)
      VStack(alignment: .leading, spacing: 4) {
        Text(book.title)
          .font(.headline)
          .foregroundStyle(Theme.ink)
          .lineLimit(2)
        Text(book.author)
          .font(.subheadline)
          .foregroundStyle(Theme.inkSoft)
        HStack(spacing: Theme.sm) {
          RatingRow(rating: book.rating, size: 11)
          if book.hasAudio {
            Label("Audio", systemImage: "headphones")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(Theme.accent)
          }
        }
      }
      Spacer()
    }
    .padding(.horizontal, Theme.lg)
    .padding(.vertical, Theme.md)
    .contentShape(Rectangle())
  }
}

#Preview {
  LibraryView()
    .modelContainer(PreviewData.container)
}
