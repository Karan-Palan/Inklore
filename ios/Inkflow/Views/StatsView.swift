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
  @Query private var sessions: [ReadingSession]
  @Query private var goals: [ReadingGoal]
  @Query private var books: [Book]

  @State private var showEditGoal = false
  @State private var showDigest = false
  @State private var showDeleteAccount = false
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
        GoalEditor(goal: goalOrCreate())
          .presentationDetents([.height(420)])
      }
      .sheet(isPresented: $showDigest) {
        DigestSettingsView()
      }
    }
    .__tenxTrackView("StatsView")
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

  // MARK: Goal ring

  private var goalRingCard: some View {
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
          Text("of goal").font(.caption).foregroundStyle(Theme.inkFaint)
        }
      }
      .frame(width: 130, height: 130)

      VStack(alignment: .leading, spacing: Theme.sm) {
        Text("This week").font(.headline).foregroundStyle(Theme.ink)
        Text("\(weeklyTotal) min")
          .font(.system(size: 34, weight: .bold, design: .rounded))
          .foregroundStyle(Theme.accent)
        Text("Goal: \(weeklyTarget) min / week")
          .font(.subheadline).foregroundStyle(Theme.inkSoft)
        if goalProgress >= 1 {
          Label("Goal reached!", systemImage: "checkmark.seal.fill")
            .font(.caption.weight(.bold)).foregroundStyle(Theme.accent)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(Theme.lg)
    .cardSurface()
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
    HStack(spacing: Theme.lg) {
      streakPill(
        icon: "flame.fill", value: "\(currentStreak)", label: "Day streak", tint: Theme.accent)
      streakPill(
        icon: "target", value: "\(goal?.dailyMinutesTarget ?? 20)", label: "Daily goal (min)",
        tint: Theme.highlightBlue)
    }
  }

  private func streakPill(icon: String, value: String, label: String, tint: Color) -> some View {
    HStack(spacing: Theme.md) {
      Image(systemName: icon)
        .font(.title2).foregroundStyle(tint)
        .frame(width: 44, height: 44)
        .background(tint.opacity(0.15), in: Circle())
      VStack(alignment: .leading, spacing: 0) {
        Text(value).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
        Text(label).font(.caption).foregroundStyle(Theme.inkFaint)
      }
      Spacer()
    }
    .padding(Theme.md)
    .frame(maxWidth: .infinity)
    .cardSurface()
  }

  // MARK: Weekly chart

  private var weeklyChartCard: some View {
    VStack(alignment: .leading, spacing: Theme.md) {
      Text("Minutes read").font(.headline).foregroundStyle(Theme.ink)
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
}

struct DayMinutes: Identifiable {
  let id = UUID()
  let day: Date
  let minutes: Int
}

/// Editable goal + profile sheet.
struct GoalEditor: View {
  @Bindable var goal: ReadingGoal
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section("Profile") {
          TextField("Your name", text: $goal.displayName)
        }
        Section("Weekly goal") {
          Stepper(
            "\(goal.weeklyMinutesTarget) min / week", value: $goal.weeklyMinutesTarget,
            in: 30...1000, step: 10)
        }
        Section("Daily goal") {
          Stepper(
            "\(goal.dailyMinutesTarget) min / day", value: $goal.dailyMinutesTarget, in: 5...240,
            step: 5)
        }
      }
      .navigationTitle("Edit goals")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
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
