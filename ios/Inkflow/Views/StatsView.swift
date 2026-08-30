import Charts
import SwiftData
import SwiftUI

/// The Stats + Profile screen. Everything here is real data computed from logged
/// reading/listening sessions: a weekly goal ring, a streak derived from actual
/// activity days, a 7-day minutes chart, and finished/in-progress counts. The
/// user can edit their name and goals.
struct StatsView: View {
  @Environment(\.modelContext) private var context
  @Environment(AuthStore.self) private var auth
  @Environment(\.appRouter) private var router
  @Query private var sessions: [ReadingSession]
  @Query private var goals: [ReadingGoal]
  @Query private var profiles: [ReaderProfile]
  @Query private var books: [Book]

  @State private var showEditGoal = false
  @State private var showDigest = false
  @State private var showDeleteAccount = false
  @State private var showReplayOnboarding = false
  @Query(sort: \Highlight.createdDate, order: .reverse) private var allHighlights: [Highlight]
  @Query(sort: \Note.createdDate, order: .reverse) private var allNotes: [Note]
  @AppStorage("digest.enabled") private var digestEnabled = false

  private var goal: ReadingGoal? { goals.first }

  private var dailyMinutes: [DayMinutes] {
    let cal = Calendar.current
    return (0..<7).reversed().map { offset -> DayMinutes in
      let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: .now))!
      let mins = sessions.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) {
        $0 + $1.minutes
      }
      return DayMinutes(day: day, minutes: mins)
    }
  }

  private var weeklyTotal: Int { dailyMinutes.reduce(0) { $0 + $1.minutes } }
  private var weeklyTarget: Int { goal?.weeklyMinutesTarget ?? 150 }
  private var goalProgress: Double { min(1, Double(weeklyTotal) / Double(max(weeklyTarget, 1))) }
  private var dailyTarget: Int { goal?.dailyMinutesTarget ?? 20 }
  private var todayMinutes: Int { dailyMinutes.last?.minutes ?? 0 }
  private var dailyProgress: Double { min(1, Double(todayMinutes) / Double(max(dailyTarget, 1))) }
  private var activeDaysThisWeek: Int { dailyMinutes.filter { $0.minutes > 0 }.count }
  private var weeklyMinutesRemaining: Int { max(weeklyTarget - weeklyTotal, 0) }
  private var finishedCount: Int { books.filter { $0.isFinished }.count }
  private var inProgressCount: Int { books.filter { $0.isStarted && !$0.isFinished }.count }
  private var totalMinutes: Int { sessions.reduce(0) { $0 + $1.minutes } }
  private var listeningMinutes: Int {
    sessions.filter { $0.wasListening }.reduce(0) { $0 + $1.minutes }
  }
  private var readingMinutes: Int {
    sessions.filter { !$0.wasListening }.reduce(0) { $0 + $1.minutes }
  }

  /// Real consecutive-day streak ending today (or yesterday).
  private var currentStreak: Int {
    let cal = Calendar.current
    let activeDays = Set(sessions.map { cal.startOfDay(for: $0.date) })
    guard !activeDays.isEmpty else { return 0 }
    var streak = 0
    var day = cal.startOfDay(for: .now)
    // Allow the streak to count from today or, if nothing today yet, from yesterday.
    if !activeDays.contains(day) {
      day = cal.date(byAdding: .day, value: -1, to: day)!
      if !activeDays.contains(day) { return 0 }
    }
    while activeDays.contains(day) {
      streak += 1
      day = cal.date(byAdding: .day, value: -1, to: day)!
    }
    return streak
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScreenHeader("You") {
          Button {
            showEditGoal = true
          } label: {
            Image(systemName: "slider.horizontal.3")
              .font(.title3.weight(.semibold))
              .foregroundStyle(Theme.ink)
              .frame(width: 32, height: 32)
          }
        }
        ScrollView {
          VStack(spacing: Theme.lg) {
            profileHeader
            goalRingCard
            listenReadSplit
            streakStrip
            digestCard
            replayOnboardingCard
            weeklyChartCard
            statTiles
            Color.clear.frame(height: Theme.sm)
          }
          .padding(.horizontal, Theme.lg)
          .padding(.top, Theme.sm)
        }
        .background(Theme.paper)
      }
      .background(Theme.paper)
      .sheet(isPresented: $showEditGoal) {
        GoalEditor(goal: goalOrCreate(), profile: profileOrCreate())
          .presentationDetents([.medium, .large])
      }
      .sheet(isPresented: $showDigest) {
        DigestSettingsView()
      }
    }
    .__tenxTrackView("StatsView")
    .alert("Replay onboarding?", isPresented: $showReplayOnboarding) {
      Button("Cancel", role: .cancel) {}
      Button("Replay onboarding") {
        router.replayOnboarding()
      }
    } message: {
      Text("Your books, downloads, notes, summaries, videos, goals, and reading progress will stay exactly as they are.")
    }
  }

  // MARK: Profile header

  private var profileHeader: some View {
    HStack(spacing: Theme.lg) {
      Circle()
        .fill(
          LinearGradient(
            colors: [Theme.accent, Theme.ink], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .frame(width: 60, height: 60)
        .overlay(
          Text(String((displayName).prefix(1)).uppercased())
            .font(.title2.weight(.bold)).foregroundStyle(.white))
      VStack(alignment: .leading, spacing: 2) {
        Text(displayName)
          .font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
        Text(auth.user?.email ?? "\(totalMinutes) minutes read all-time")
          .font(.subheadline).foregroundStyle(Theme.inkSoft)
          .lineLimit(1)
      }
      Spacer()
      Menu {
        Button(role: .destructive) {
          auth.signOut()
        } label: {
          Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
        }
        Button(role: .destructive) {
          showDeleteAccount = true
        } label: {
          Label("Delete account", systemImage: "trash")
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.title2).foregroundStyle(Theme.inkSoft)
      }
    }
    .padding(.vertical, Theme.sm)
    .alert("Delete account?", isPresented: $showDeleteAccount) {
      Button("Cancel", role: .cancel) {}
      Button("Delete", role: .destructive) {
        Task { await auth.deleteAccount() }
      }
    } message: {
      Text(
        "This permanently deletes your account and signs you out. Books and progress on this device are not affected."
      )
    }
  }

  private var displayName: String {
    if let name = auth.user?.fullName, !name.isEmpty { return name }
    let goalName = goal?.displayName ?? ""
    return goalName.isEmpty ? "Reader" : goalName
  }

  private var replayOnboardingCard: some View {
    Button {
      showReplayOnboarding = true
    } label: {
      HStack(spacing: Theme.md) {
        Image(systemName: "sparkles.rectangle.stack")
          .font(.title3.weight(.semibold))
          .foregroundStyle(Theme.accent)
          .frame(width: 30)
        VStack(alignment: .leading, spacing: 2) {
          Text("Replay onboarding")
            .font(.headline)
            .foregroundStyle(Theme.ink)
          Text("Show the intro again without clearing anything")
            .font(.caption)
            .foregroundStyle(Theme.inkSoft)
        }
        Spacer()
        Image(systemName: "arrow.clockwise")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Theme.inkFaint)
      }
      .padding(Theme.lg)
      .cardSurface()
    }
    .buttonStyle(.plain)
  }

  // MARK: Goal ring

  private var goalRingCard: some View {
    VStack(alignment: .leading, spacing: Theme.lg) {
      HStack(spacing: Theme.xl) {
        ZStack {
          Circle().stroke(Theme.surfaceAlt, lineWidth: 14)
          Circle()
            .trim(from: 0, to: goalProgress)
            .stroke(
              AngularGradient(
                colors: [Theme.accent, Theme.highlightYellow, Theme.accent], center: .center),
              style: StrokeStyle(lineWidth: 14, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .animation(.smooth, value: goalProgress)
          VStack(spacing: 2) {
            Text("\(Int(goalProgress * 100))%")
              .font(.title.weight(.bold)).foregroundStyle(Theme.ink)
            Text("this week").font(.caption).foregroundStyle(Theme.inkFaint)
          }
        }
        .frame(width: 126, height: 126)

        VStack(alignment: .leading, spacing: Theme.sm) {
          Text(weeklyGoalEyebrow)
            .font(.caption.weight(.bold))
            .tracking(0.9)
            .foregroundStyle(Theme.inkFaint)
          Text("\(weeklyTotal) min")
            .font(.system(size: 34, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.accent)
          Text(weeklyGoalDetail)
            .font(.subheadline).foregroundStyle(Theme.inkSoft)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
      }

      VStack(alignment: .leading, spacing: Theme.sm) {
        HStack {
          Label("Today", systemImage: dailyProgress >= 1 ? "checkmark.circle.fill" : "sun.max.fill")
            .font(.caption.weight(.bold))
            .foregroundStyle(dailyProgress >= 1 ? Theme.accent : Theme.inkSoft)
          Spacer()
          Text(dailyGoalDetail)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.inkSoft)
        }
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(Theme.surfaceAlt)
            Capsule()
              .fill(dailyProgress >= 1 ? Theme.accent : Theme.highlightBlue)
              .frame(width: max(dailyProgress == 0 ? 0 : 6, geo.size.width * dailyProgress))
          }
        }
        .frame(height: 8)
      }
    }
    .padding(Theme.lg)
    .cardSurface()
  }

  private var weeklyGoalEyebrow: String {
    goalProgress >= 1 ? "WEEKLY GOAL COMPLETE" : "YOUR WEEKLY RHYTHM"
  }

  private var weeklyGoalDetail: String {
    if goalProgress >= 1 { return "You showed up for yourself. Beautiful work." }
    if weeklyTotal == 0 { return "A small first session is all it takes to begin." }
    return "\(weeklyMinutesRemaining) min to reach your \(weeklyTarget)-min goal"
  }

  private var dailyGoalDetail: String {
    if dailyProgress >= 1 { return "Daily goal complete" }
    return todayMinutes == 0 ? "Start with \(dailyTarget) min" : "\(todayMinutes) of \(dailyTarget) min"
  }

  // MARK: Read vs listen split

  private var listenReadSplit: some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      Text("How you read").font(.headline).foregroundStyle(Theme.ink)
      HStack(spacing: Theme.lg) {
        splitTile(
          icon: "book.fill", minutes: readingMinutes, label: "Reading",
          tint: Theme.accent)
        splitTile(
          icon: "headphones", minutes: listeningMinutes, label: "Listening",
          tint: Theme.highlightBlue)
      }
      let total = CGFloat(max(readingMinutes + listeningMinutes, 1))
      GeometryReader { geo in
        HStack(spacing: 2) {
          Capsule().fill(Theme.accent)
            .frame(width: geo.size.width * CGFloat(readingMinutes) / total)
          Capsule().fill(Theme.highlightBlue)
        }
      }
      .frame(height: 8)
      Text(
        "\(readingMinutes) min read · \(listeningMinutes) min listened, all-time"
      )
      .font(.caption).foregroundStyle(Theme.inkFaint)
      if totalMinutes == 0 {
        Text("Your mix will appear after your first reading session.")
          .font(.caption)
          .foregroundStyle(Theme.inkSoft)
      }
    }
    .padding(Theme.lg)
    .cardSurface()
  }

  private func splitTile(icon: String, minutes: Int, label: String, tint: Color) -> some View {
    HStack(spacing: Theme.md) {
      Image(systemName: icon)
        .font(.title3).foregroundStyle(tint)
        .frame(width: 40, height: 40)
        .background(tint.opacity(0.15), in: Circle())
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text("\(minutes)")
            .font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
          Text("min").font(.caption).foregroundStyle(Theme.inkFaint)
        }
        Text(label).font(.caption).foregroundStyle(Theme.inkSoft)
      }
      Spacer()
    }
    .padding(Theme.md)
    .frame(maxWidth: .infinity)
    .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.radiusMd))
  }

  // MARK: Streak

  private var streakStrip: some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("KEEP THE SPARK GOING")
            .font(.caption.weight(.bold))
            .tracking(1)
            .foregroundStyle(Theme.inkFaint)
          Text(streakMessage)
            .font(.headline)
            .foregroundStyle(Theme.ink)
        }
        Spacer()
        Image(systemName: currentStreak > 0 ? "flame.fill" : "flame")
          .font(.title2)
          .foregroundStyle(Theme.accent)
          .frame(width: 44, height: 44)
          .background(Theme.accent.opacity(0.12), in: Circle())
      }

      HStack(spacing: 0) {
        ForEach(Array(dailyMinutes.enumerated()), id: \.offset) { index, day in
          VStack(spacing: 6) {
            Circle()
              .fill(day.minutes > 0 ? Theme.accent : Theme.surfaceAlt)
              .frame(width: 26, height: 26)
              .overlay {
                if day.minutes > 0 {
                  Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                }
              }
              .overlay {
                if Calendar.current.isDateInToday(day.day) {
                  Circle().strokeBorder(Theme.ink, lineWidth: 1.5).padding(-3)
                }
              }
            Text(day.day, format: .dateTime.weekday(.narrow))
              .font(.caption2.weight(index == dailyMinutes.count - 1 ? .bold : .regular))
              .foregroundStyle(Theme.inkSoft)
          }
          .frame(maxWidth: .infinity)
        }
      }

      HStack(spacing: Theme.lg) {
        miniMetric(value: "\(currentStreak)", label: currentStreak == 1 ? "day streak" : "day streak")
        miniMetric(value: "\(activeDaysThisWeek)/7", label: "days this week")
        miniMetric(value: "\(dailyTarget)", label: "min each day")
      }
    }
    .padding(Theme.lg)
    .cardSurface()
  }

  private var streakMessage: String {
    if currentStreak == 0 { return "Your next page starts a new streak." }
    if currentStreak == 1 { return "One day in—come back tomorrow." }
    return "\(currentStreak) days of making space to read."
  }

  private func miniMetric(value: String, label: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(value)
        .font(.subheadline.weight(.bold))
        .foregroundStyle(Theme.ink)
      Text(label)
        .font(.caption2)
        .foregroundStyle(Theme.inkFaint)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: Weekly chart

  private var weeklyChartCard: some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      HStack(alignment: .firstTextBaseline) {
        Text("Minutes read").font(.headline).foregroundStyle(Theme.ink)
        Spacer()
        Text("\(activeDaysThisWeek) of 7 days")
          .font(.caption.weight(.semibold))
          .foregroundStyle(Theme.inkSoft)
      }
      Chart(dailyMinutes) { point in
        BarMark(x: .value("Day", point.day, unit: .day), y: .value("Minutes", point.minutes))
          .foregroundStyle(Theme.accent.gradient)
          .cornerRadius(6)
        RuleMark(y: .value("Daily target", weeklyTarget / 7))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
          .foregroundStyle(Theme.inkFaint)
      }
      .frame(height: 200)
      .chartYScale(domain: 0...max(60, (dailyMinutes.map(\.minutes).max() ?? 60) + 10))
      .chartXAxis {
        AxisMarks(values: .stride(by: .day)) { _ in
          AxisValueLabel(format: .dateTime.weekday(.narrow))
        }
      }
      .accessibilityLabel("Minutes read each day this week")
      Text("The dotted line is your \(max(1, weeklyTarget / 7))-minute daily pace.")
        .font(.caption)
        .foregroundStyle(Theme.inkFaint)
    }
    .padding(Theme.lg)
    .cardSurface()
  }

  // MARK: Tiles

  private var statTiles: some View {
    HStack(spacing: Theme.lg) {
      tile(value: "\(finishedCount)", label: "Books finished", icon: "checkmark.circle.fill")
      tile(value: "\(inProgressCount)", label: "In progress", icon: "book.fill")
    }
  }

  private func tile(value: String, label: String, icon: String) -> some View {
    VStack(alignment: .leading, spacing: Theme.sm) {
      Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent)
      Text(value)
        .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
      Text(label).font(.subheadline).foregroundStyle(Theme.inkSoft)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Theme.lg)
    .cardSurface()
  }

  // MARK: Daily email digest

  private var digestCard: some View {
    Button {
      showDigest = true
    } label: {
      HStack(spacing: Theme.lg) {
        Image(systemName: "envelope.badge.fill")
          .font(.title2).foregroundStyle(Theme.accent)
          .frame(width: 44, height: 44)
          .background(Theme.accent.opacity(0.15), in: Circle())
        VStack(alignment: .leading, spacing: 2) {
          Text("Daily notes email").font(.headline).foregroundStyle(Theme.ink)
          Text(
            digestEnabled
              ? "On · your highlights arrive each morning"
              : "Get your highlights emailed every morning"
          )
          .font(.caption).foregroundStyle(Theme.inkSoft)
        }
        Spacer()
        Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
          .foregroundStyle(Theme.inkFaint)
      }
      .padding(Theme.lg)
      .cardSurface()
    }
    .buttonStyle(.plain)
  }

  private func goalOrCreate() -> ReadingGoal {
    if let goal { return goal }
    let g = ReadingGoal()
    context.insert(g)
    return g
  }

  private func profileOrCreate() -> ReaderProfile {
    if let profile = profiles.first { return profile }
    let profile = ReaderProfile(hasCompletedOnboarding: OnboardingFlag.completed)
    context.insert(profile)
    return profile
  }
}

struct DayMinutes: Identifiable {
  let id = UUID()
  let day: Date
  let minutes: Int
}

/// One in-app home for the durable onboarding choices and reading target.
struct GoalEditor: View {
  @Bindable var goal: ReadingGoal
  @Bindable var profile: ReaderProfile
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss
  @State private var saveError: String?
  @State private var draftDisplayName: String
  @State private var draftConsumeModeRaw: String
  @State private var draftGenreID: String
  @State private var draftDailyMinutes: Int
  @State private var draftWeeklyMinutes: Int

  init(goal: ReadingGoal, profile: ReaderProfile) {
    self.goal = goal
    self.profile = profile
    _draftDisplayName = State(initialValue: goal.displayName)
    _draftConsumeModeRaw = State(initialValue: profile.consumeModeRaw)
    _draftGenreID = State(initialValue: profile.selectedGenreID)
    _draftDailyMinutes = State(initialValue: profile.dailyMinutesTarget)
    _draftWeeklyMinutes = State(initialValue: goal.weeklyMinutesTarget)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("Profile") {
          TextField("Your name", text: $draftDisplayName)
        }
        Section("How you read") {
          Picker("Default mode", selection: $draftConsumeModeRaw) {
            ForEach(ConsumeMode.allCases) { mode in
              Label(mode.rawValue, systemImage: mode.icon).tag(mode.rawValue)
            }
          }
          Picker("Starter shelf", selection: $draftGenreID) {
            ForEach(ReadingGenre.all) { genre in
              Label(genre.name, systemImage: genre.icon).tag(genre.id)
            }
          }
        }
        Section("Daily rhythm") {
          Picker("Daily goal", selection: dailyMinutes) {
            ForEach(DailyGoalOption.all) { option in
              Text("\(option.label) · \(option.shortBlurb)").tag(option.minutes)
            }
          }
          Text("Your weekly target starts at five reading days and can be adjusted below.")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
        }
        Section("Weekly goal") {
          Stepper(
            "\(draftWeeklyMinutes) min / week", value: $draftWeeklyMinutes,
            in: 30...1000, step: 10)
          Text("Changing the weekly goal here does not change your daily rhythm.")
            .font(.footnote)
            .foregroundStyle(Theme.inkSoft)
        }
        if let saveError {
          Section {
            Text(saveError)
              .font(.footnote)
              .foregroundStyle(.red)
          }
        }
      }
      .navigationTitle("Reading preferences")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { save() }
            .fontWeight(.semibold)
        }
      }
    }
  }

  private var dailyMinutes: Binding<Int> {
    Binding(
      get: { draftDailyMinutes },
      set: { minutes in
        draftDailyMinutes = minutes
        draftWeeklyMinutes = minutes * 5
      }
    )
  }

  private func save() {
    let genre = ReadingGenre.named(draftGenreID) ?? ReadingGenre.all[0]
    let mode = ConsumeMode(rawValue: draftConsumeModeRaw) ?? .both
    do {
      goal.displayName = draftDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
      try OnboardingPersistence.savePreferences(
        profile: profile,
        goal: goal,
        consumeMode: mode,
        dailyMinutes: draftDailyMinutes,
        weeklyMinutes: draftWeeklyMinutes,
        genre: genre,
        in: context
      )
      dismiss()
    } catch {
      saveError = "We couldn't save those preferences. Please try again."
    }
  }
}

extension View {
  /// Standard white card surface used across stats + detail screens.
  func cardSurface() -> some View {
    background(
      Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
    )
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusLg, style: .continuous)
        .strokeBorder(Theme.hairline, lineWidth: 1))
  }
}

#Preview {
  StatsView()
    .environment(AuthStore())
    .modelContainer(PreviewData.container)
}
