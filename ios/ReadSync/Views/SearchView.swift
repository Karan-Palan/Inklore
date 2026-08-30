import SwiftData
import SwiftUI

/// Discover real, freely-readable books from two legal sources: Project
/// Gutenberg (full EPUBs with images & formatting) and the Internet Archive
/// (plain-text fallback). Results are unified into one list with a source badge;
/// tapping download fetches the right format and saves it to the local library.
struct SearchView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.appRouter) private var router
  @Query private var library: [Book]

  @State private var query = ""
  @State private var results: [DiscoverResult] = []
  @State private var isSearching = false
  @State private var errorText: String?
  @State private var downloadError: String?
  @State private var downloadingIDs: Set<String> = []
  @State private var filters = SearchFilters()
  @State private var showFilters = false
  @State private var searchTask: Task<Void, Never>?
  @State private var readerBook: Book?
  @State private var recGenre: ReadingGenre = OnboardingFlag.selectedGenre
  @State private var recPicks: [GenreBook] = []
  @State private var relatedPicks: [(ReadingGenre, [GenreBook])] = []
  @FocusState private var searchFocused: Bool

  private func savedBook(for id: String) -> Book? {
    library.first { $0.sourceIdentifier == id }
  }

  private var savedIdentifiers: Set<String> {
    Set(library.map(\.sourceIdentifier).filter { !$0.isEmpty })
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        searchHeader
        if !query.isEmpty || !results.isEmpty {
          filterBar
        }
        Group {
          if query.isEmpty && results.isEmpty {
            emptyPrompt
          } else if isSearching {
            ProgressView("Searching free libraries…")
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          } else if let errorText {
            errorState(errorText)
          } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
          } else {
            resultsList
          }
        }
      }
      .background(Theme.paper)
      .navigationBarHidden(true)
      .onChange(of: query) { _, newValue in
        scheduleSearch(for: newValue)
      }
      .onAppear {
        refreshRecommendations()
        consumePendingSearch()
      }
      .onChange(of: router.pendingSearch) { _, _ in consumePendingSearch() }
      .sheet(isPresented: $showFilters) {
        filterSheet
      }
      .alert(
        "Download failed", isPresented: .constant(downloadError != nil),
        presenting: downloadError
      ) { _ in
        Button("OK", role: .cancel) { downloadError = nil }
      } message: { message in
        Text(message)
      }
      .fullScreenCover(item: $readerBook) { book in
        BookReader(book: book)
      }
    }
    .__tenxTrackView("SearchView")
  }

  // MARK: Search header

  private var searchHeader: some View {
    HStack(spacing: Theme.sm) {
      if !query.isEmpty || !results.isEmpty {
        Button {
          clearSearch()
        } label: {
          Image(systemName: "chevron.left")
            .font(.headline.weight(.semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: 32, height: 32)
        }
      }

      HStack(spacing: Theme.sm) {
        Image(systemName: "magnifyingglass")
          .foregroundStyle(Theme.inkFaint)
        TextField("Search free books, authors, topics", text: $query)
          .focused($searchFocused)
          .submitLabel(.search)
          .autocorrectionDisabled()
          .textInputAutocapitalization(.words)
          .onSubmit {
            searchTask?.cancel()
            Task { await runSearch() }
          }
        if !query.isEmpty {
          Button {
            query = ""
            searchFocused = true
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(Theme.inkFaint)
          }
        }
      }
      .padding(.horizontal, Theme.md)
      .padding(.vertical, 11)
      .background(Theme.surfaceAlt, in: Capsule())
    }
    .padding(.horizontal, Theme.lg)
    .padding(.top, Theme.sm)
    .padding(.bottom, Theme.xs)
    .background(Theme.paper)
  }

  // MARK: Filter bar

  private var filterBar: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Theme.sm) {
        Button {
          showFilters = true
        } label: {
          HStack(spacing: 5) {
            Image(systemName: "slider.horizontal.3")
            if filters.activeCount > 0 {
              Text("\(filters.activeCount)")
                .font(.caption2.weight(.bold))
                .padding(5)
                .background(Theme.accent, in: Circle())
                .foregroundStyle(.white)
            }
          }
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(filters.activeCount > 0 ? Theme.accent : Theme.ink)
          .padding(.horizontal, Theme.md)
          .padding(.vertical, 7)
          .background(Theme.surfaceAlt, in: Capsule())
        }

        quickPill(filters.source.rawValue, active: filters.source != .all)
        quickPill(filters.format.rawValue, active: filters.format != .all)
        quickPill(filters.language.rawValue, active: filters.language != .any)
        quickPill(filters.sort.rawValue, active: filters.sort != .relevance)
      }
      .padding(.horizontal, Theme.lg)
      .padding(.vertical, Theme.sm)
    }
    .background(Theme.paper)
  }

  private func quickPill(_ text: String, active: Bool) -> some View {
    Button {
      showFilters = true
    } label: {
      Text(text)
        .font(.subheadline.weight(.medium))
        .foregroundStyle(active ? .white : Theme.ink)
        .padding(.horizontal, Theme.md)
        .padding(.vertical, 7)
        .background(active ? Theme.accent : Theme.surfaceAlt, in: Capsule())
    }
  }

  private var filterSheet: some View {
    NavigationStack {
      Form {
        Picker("Source", selection: $filters.source) {
          ForEach(SourceFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Format", selection: $filters.format) {
          ForEach(FormatFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Language", selection: $filters.language) {
          ForEach(LanguageFilter.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Sort by", selection: $filters.sort) {
          ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
        }
        if filters.activeCount > 0 {
          Button("Reset filters", role: .destructive) {
            filters = SearchFilters()
          }
        }
      }
      .navigationTitle("Filters")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Apply") {
            showFilters = false
            Task { await runSearch() }
          }
          .fontWeight(.semibold)
        }
      }
    }
    .presentationDetents([.medium])
    .tint(Theme.accent)
  }

  private var emptyPrompt: some View {
    ScrollView {
      VStack(spacing: Theme.lg) {
        Image(systemName: "books.vertical")
          .font(.system(size: 52))
          .foregroundStyle(Theme.accent)
        Text("Find your next read")
          .font(.title2.weight(.bold))
          .foregroundStyle(Theme.ink)
        Text(
          "Search real books from Project Gutenberg and the Internet Archive, and download them straight to your library."
        )
        .font(.subheadline)
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.inkSoft)
        .padding(.horizontal, Theme.xl)

        recommendationRail(
          title: "RECOMMENDED IN \(recGenre.name.uppercased())",
          tint: recGenre.tint, picks: recPicks,
          trailing: {
            Button {
              refreshRecommendations()
            } label: {
              Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(Theme.accent)
            }
          })

        ForEach(relatedPicks, id: \.0.id) { related, picks in
          recommendationRail(
            title: "BECAUSE YOU LIKE \(recGenre.name.uppercased()) · \(related.name.uppercased())",
            tint: related.tint, picks: picks, trailing: { EmptyView() })
        }
      }
      .padding()
    }
  }

  @ViewBuilder
  private func recommendationRail(
    title: String, tint: UInt, picks: [GenreBook],
    @ViewBuilder trailing: () -> some View
  ) -> some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      HStack {
        Text(title)
          .font(.caption.weight(.bold))
          .tracking(1)
          .foregroundStyle(Theme.inkFaint)
          .lineLimit(1)
        Spacer()
        trailing()
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(alignment: .top, spacing: Theme.md) {
          ForEach(picks) { rec in
            Button {
              query = rec.searchQuery
              Task { await runSearch() }
            } label: {
              VStack(spacing: 6) {
                GenreCoverThumb(url: rec.coverURL, tint: tint, width: 96)
                Text(rec.title)
                  .font(.caption2.weight(.semibold))
                  .foregroundStyle(Theme.ink)
                  .lineLimit(2)
                  .multilineTextAlignment(.center)
                  .frame(width: 96)
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .padding(.top, Theme.sm)
  }

  /// Re-rolls a fresh shuffled set of recommendations for the reader's genre and
  /// its related genres, so the empty state feels new on every visit/refresh.
  private func refreshRecommendations() {
    recGenre = OnboardingFlag.selectedGenre
    recPicks = recGenre.recommendations(4)
    relatedPicks = recGenre.related.map { ($0, $0.recommendations(4)) }
  }

  /// Drops a router-provided query into the field (from the empty library or
  /// onboarding) and kicks off a search, then clears the pending value.
  private func consumePendingSearch() {
    guard let pending = router.pendingSearch, !pending.isEmpty else { return }
    router.pendingSearch = nil
    query = pending
    Task { await runSearch() }
  }

  /// Returns from a results view back to the recommendation empty state.
  private func clearSearch() {
    searchTask?.cancel()
    query = ""
    results = []
    errorText = nil
    isSearching = false
    refreshRecommendations()
  }

  private func errorState(_ message: String) -> some View {
    ContentUnavailableView {
      Label("Couldn't search", systemImage: "wifi.exclamationmark")
    } description: {
      Text(message)
    } actions: {
      Button("Try again") { Task { await runSearch() } }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
    }
  }

  private var resultsList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(results) { result in
          resultRow(result)
          Divider().padding(.leading, Theme.lg)
        }
      }
      .padding(.top, Theme.sm)
    }
  }

  private func resultRow(_ result: DiscoverResult) -> some View {
    let isSaved = savedIdentifiers.contains(result.id)
    let isDownloading = downloadingIDs.contains(result.id)
    return HStack(alignment: .top, spacing: Theme.md) {
      cover(for: result)

      VStack(alignment: .leading, spacing: 4) {
        Text(result.title)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(Theme.ink)
          .lineLimit(2)
        Text(result.author)
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
          .lineLimit(1)
        sourceBadge(result.source)
        if !result.detail.isEmpty {
          Text(result.detail)
            .font(.caption2)
            .foregroundStyle(Theme.inkFaint)
            .lineLimit(2)
        }
      }
      Spacer(minLength: 0)

      Group {
        if isSaved {
          Button {
            if let book = savedBook(for: result.id) {
              book.lastOpenedDate = .now
              readerBook = book
            }
          } label: {
            VStack(spacing: 3) {
              Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
              Text("Read")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.accent)
            }
          }
          .buttonStyle(.plain)
        } else if isDownloading {
          ProgressView()
        } else {
          Button {
            Task { await download(result) }
          } label: {
            Image(systemName: "arrow.down.circle")
              .font(.title2)
              .foregroundStyle(Theme.accent)
          }
        }
      }
    }
    .padding(.horizontal, Theme.lg)
    .padding(.vertical, Theme.md)
  }

  private func cover(for result: DiscoverResult) -> some View {
    RoundedRectangle(cornerRadius: Theme.radiusSm)
      .fill(
        LinearGradient(
          colors: [Theme.accent.opacity(0.8), Theme.ink], startPoint: .topLeading,
          endPoint: .bottomTrailing)
      )
      .frame(width: 62, height: 92)
      .overlay {
        if let url = result.coverURL {
          AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
              image.resizable().scaledToFill()
            case .failure:
              Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.85))
            default:
              ProgressView().tint(.white)
            }
          }
          .frame(width: 62, height: 92)
          .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
        } else {
          Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.85))
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
  }

  private func sourceBadge(_ source: BookSource) -> some View {
    HStack(spacing: 4) {
      Image(systemName: source.deliversEpub ? "doc.richtext" : "doc.plaintext")
        .font(.system(size: 9, weight: .bold))
      Text(source.deliversEpub ? "EPUB · \(source.rawValue)" : "Text · \(source.rawValue)")
        .font(.system(size: 10, weight: .semibold))
    }
    .foregroundStyle(source.badgeColor)
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(source.badgeColor.opacity(0.12), in: Capsule())
  }

  // MARK: Actions

  /// Debounced search-as-you-type: cancels any in-flight search and waits a beat
  /// after the last keystroke before hitting the network.
  private func scheduleSearch(for newValue: String) {
    searchTask?.cancel()
    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      results = []
      errorText = nil
      isSearching = false
      return
    }
    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      await runSearch()
    }
  }

  private func runSearch() async {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isSearching = true
    errorText = nil
    let outcome = await BookSearch.search(trimmed, filters: filters)
    guard !Task.isCancelled else { return }
    results = outcome.results
    errorText = outcome.error
    isSearching = false
  }

  private func download(_ result: DiscoverResult) async {
    downloadingIDs.insert(result.id)
    defer { downloadingIDs.remove(result.id) }
    do {
      try await BookDownloader.download(result, into: context)
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
      downloadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
  }
}

#Preview {
  SearchView()
    .modelContainer(PreviewData.container)
}
