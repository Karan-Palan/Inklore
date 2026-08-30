import SwiftData
import SwiftUI
import UIKit
import XCTest

@testable import Inkflow

@MainActor
final class OnboardingPersistenceTests: XCTestCase {
  func testBrandPaletteMaintainsContrastInBothAppearances() {
    let light = UITraitCollection(userInterfaceStyle: .light)
    let dark = UITraitCollection(userInterfaceStyle: .dark)

    let lightPaper = UIColor(Theme.paper).resolvedColor(with: light)
    let darkPaper = UIColor(Theme.paper).resolvedColor(with: dark)
    let lightInk = UIColor(Theme.ink).resolvedColor(with: light)
    let darkInk = UIColor(Theme.ink).resolvedColor(with: dark)
    let darkDataAccent = UIColor(Color(adaptiveAccentHex: 0x0F5C5B)).resolvedColor(with: dark)

    XCTAssertGreaterThan(luminance(lightPaper), luminance(darkPaper))
    XCTAssertGreaterThan(luminance(lightPaper), luminance(lightInk))
    XCTAssertGreaterThan(luminance(darkInk), luminance(darkPaper))
    XCTAssertGreaterThan(luminance(darkDataAccent), luminance(darkPaper) + 0.25)
    XCTAssertNotEqual(lightPaper, darkPaper)
    XCTAssertNotEqual(lightInk, darkInk)
  }

  func testSavePersistsSelectionsRecommendationsAndGoal() throws {
    let defaults = UserDefaults.standard
    let previousCompletionFlag = defaults.object(forKey: OnboardingFlag.key)
    defer {
      if let previousCompletionFlag {
        defaults.set(previousCompletionFlag, forKey: OnboardingFlag.key)
      } else {
        defaults.removeObject(forKey: OnboardingFlag.key)
      }
    }
    let schema = Schema([ReaderProfile.self, ReadingGoal.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = container.mainContext

    let state = OnboardingState()
    state.consumeMode = .listening
    state.dailyMinutes = 45
    state.genre = ReadingGenre.named("philosophy")!
    let recommendations = Array(state.genre.pool.prefix(4))

    try OnboardingPersistence.save(
      state: state,
      recommendations: recommendations,
      profiles: [],
      goals: [],
      in: context
    )

    let profiles = try context.fetch(FetchDescriptor<ReaderProfile>())
    XCTAssertEqual(profiles.count, 1)
    XCTAssertEqual(profiles[0].hasCompletedOnboarding, false)
    XCTAssertEqual(profiles[0].consumeMode, .listening)
    XCTAssertEqual(profiles[0].dailyMinutesTarget, 45)
    XCTAssertEqual(profiles[0].weeklyMinutesTarget, 225)
    XCTAssertEqual(profiles[0].selectedGenreID, "philosophy")
    XCTAssertEqual(profiles[0].onboardingRecommendationISBNs, recommendations.map(\.isbn))

    let goals = try context.fetch(FetchDescriptor<ReadingGoal>())
    XCTAssertEqual(goals.count, 1)
    XCTAssertEqual(goals[0].dailyMinutesTarget, 45)
    XCTAssertEqual(goals[0].weeklyMinutesTarget, 225)

    try OnboardingPersistence.finalizeOnboarding(in: context)
    XCTAssertEqual(profiles[0].hasCompletedOnboarding, true)
  }

  func testSaveUpsertsInsteadOfCreatingDuplicateProfileOrGoal() throws {
    let schema = Schema([ReaderProfile.self, ReadingGoal.self])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [configuration])
    let context = container.mainContext
    let profile = ReaderProfile()
    let goal = ReadingGoal()
    context.insert(profile)
    context.insert(goal)
    try context.save()

    let state = OnboardingState()
    state.consumeMode = .reading
    state.dailyMinutes = 10
    state.genre = ReadingGenre.named("scifi")!
    let recommendations = Array(state.genre.pool.prefix(4))

    try OnboardingPersistence.save(
      state: state,
      recommendations: recommendations,
      profiles: [profile],
      goals: [goal],
      in: context
    )

    XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReaderProfile>()), 1)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReadingGoal>()), 1)
    XCTAssertEqual(profile.consumeMode, .reading)
    XCTAssertEqual(profile.selectedGenreID, "scifi")
    XCTAssertEqual(goal.dailyMinutesTarget, 10)
    XCTAssertEqual(goal.weeklyMinutesTarget, 50)
  }

  func testPaginatorFindsOffsetsAtPageBoundariesAndPastTheEnd() {
    let text = String(repeating: "A compact paragraph for pagination. ", count: 2_000)
    let paginator = Paginator.paginate(
      text: text,
      font: .systemFont(ofSize: 18),
      textColor: .label,
      lineSpacing: 5,
      size: CGSize(width: 280, height: 420))

    XCTAssertGreaterThan(paginator.pageCount, 2)
    for (index, range) in paginator.pageRanges.enumerated() {
      XCTAssertEqual(paginator.pageIndex(for: range.location), index)
      XCTAssertEqual(paginator.startOffset(of: index), range.location)
    }
    XCTAssertEqual(
      paginator.pageIndex(for: (text as NSString).length + 10), paginator.pageCount - 1)
  }

  func testNativeReaderPositionsMirrorIntoTheCanonicalTextOffset() {
    let text = String(repeating: "x", count: 1_000)
    let epub = Book(
      title: "EPUB", author: "Author", bookDescription: "", category: "",
      coverHexStart: 0, coverHexEnd: 0, storedText: text, format: .epub, spineCount: 4)
    epub.spineIndex = 1
    epub.chapterScroll = 0.5

    // A native-only position from a previous release still opens at the same
    // place, then gets persisted as the shared read/listen anchor.
    XCTAssertEqual(epub.canonicalCharacterOffset, 375)
    epub.restoreCanonicalCharacterOffset()
    XCTAssertEqual(epub.charOffset, 375)

    XCTAssertTrue(
      epub.updateEpubPosition(spineIndex: 2, scroll: 0.25, spineCount: 4))
    XCTAssertEqual(epub.charOffset, 562)
    XCTAssertEqual(epub.progress, 0.562, accuracy: 0.001)

    // An old reader view must not overwrite a newer player checkpoint.
    XCTAssertTrue(epub.updateCharacterOffset(800))
    XCTAssertFalse(epub.updateEpubPosition(spineIndex: 1, scroll: 0.5, spineCount: 4))
    XCTAssertEqual(epub.charOffset, 800)
    XCTAssertEqual(epub.spineIndex, 2)

    XCTAssertTrue(
      epub.updateEpubPosition(
        spineIndex: 3, scroll: 0.96, spineCount: 4, allowingBackward: true))
    XCTAssertTrue(epub.isFinished)
    XCTAssertTrue(
      epub.updateEpubPosition(
        spineIndex: 0, scroll: 0, spineCount: 4, allowingBackward: true))
    XCTAssertEqual(epub.canonicalCharacterOffset, 0)
    XCTAssertFalse(epub.isFinished)
  }

  func testPdfAndAudioHandoffsCannotRollBackProgress() {
    let text = String(repeating: "x", count: 1_000)
    let pdf = Book(
      title: "PDF", author: "Author", bookDescription: "", category: "",
      coverHexStart: 0, coverHexEnd: 0, storedText: text, format: .pdf, pdfPageCount: 10)
    pdf.pdfPageIndex = 3

    XCTAssertEqual(pdf.canonicalCharacterOffset, 300)
    pdf.restoreCanonicalCharacterOffset()
    XCTAssertEqual(pdf.charOffset, 300)

    // Audio can retain its precise offset while also updating the nearest
    // native PDF page that the visual reader needs to restore.
    XCTAssertTrue(pdf.updateCharacterOffset(780))
    XCTAssertTrue(
      pdf.updatePdfPosition(pageIndex: 7, pageCount: 10, characterOffset: 780))
    XCTAssertEqual(pdf.charOffset, 780)
    XCTAssertEqual(pdf.pdfPageIndex, 7)
    XCTAssertEqual(pdf.progress, 0.78, accuracy: 0.001)

    XCTAssertFalse(pdf.updatePdfPosition(pageIndex: 3, pageCount: 10))
    XCTAssertEqual(pdf.charOffset, 780)
    XCTAssertEqual(pdf.pdfPageIndex, 7)

    // A seek to the beginning must replace both the text anchor and the
    // native locator; the legacy native fallback must not resurrect progress.
    pdf.isFinished = true
    XCTAssertTrue(pdf.updateCharacterOffset(0, allowingBackward: true))
    XCTAssertTrue(
      pdf.updatePdfPosition(
        pageIndex: 0, pageCount: 10, characterOffset: 0, allowingBackward: true))
    XCTAssertEqual(pdf.canonicalCharacterOffset, 0)
    XCTAssertEqual(pdf.pdfPageIndex, 0)
    XCTAssertFalse(pdf.isFinished)
  }

  func testChapterSummaryRejectsContentsAndCopyrightBoilerplate() {
    let section = ChapterSummarySection(
      id: "summary-test",
      title: "Part 2: The Rules",
      text: """
        Rule #1: Work Deeply Rule #2: Embrace Boredom Rule #3: Quit Social Media
        Copyright © 2016 by Example Author. Cover design by Example Studio.
        Deep work trains the mind to concentrate without distraction for demanding tasks.
        Protecting deliberate blocks of attention makes difficult work more consistent and valuable.
        """,
      startOffset: 0,
      endOffset: 400)

    let markdown = ChapterSummaryContent.markdown(for: section)
    XCTAssertTrue(markdown.contains("Deep work trains the mind"))
    XCTAssertTrue(markdown.contains("Protecting deliberate blocks"))
    XCTAssertFalse(markdown.localizedCaseInsensitiveContains("copyright"))
    XCTAssertFalse(markdown.contains("Rule #1"))
  }

  private func luminance(_ color: UIColor) -> CGFloat {
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue
  }
}
