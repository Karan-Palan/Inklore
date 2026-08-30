import SwiftData
import UIKit
import XCTest

@testable import ReadSync

@MainActor
final class OnboardingPersistenceTests: XCTestCase {
  func testSavePersistsSelectionsRecommendationsAndGoal() throws {
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
    XCTAssertEqual(profiles[0].hasCompletedOnboarding, true)
    XCTAssertEqual(profiles[0].consumeMode, .listening)
    XCTAssertEqual(profiles[0].dailyMinutesTarget, 45)
    XCTAssertEqual(profiles[0].weeklyMinutesTarget, 225)
    XCTAssertEqual(profiles[0].selectedGenreID, "philosophy")
    XCTAssertEqual(profiles[0].onboardingRecommendationISBNs, recommendations.map(\.isbn))

    let goals = try context.fetch(FetchDescriptor<ReadingGoal>())
    XCTAssertEqual(goals.count, 1)
    XCTAssertEqual(goals[0].dailyMinutesTarget, 45)
    XCTAssertEqual(goals[0].weeklyMinutesTarget, 225)
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
}
