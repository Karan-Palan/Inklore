import SwiftData
import SwiftUI

/// Settings for the reader's local-time daily and weekly email recaps.
struct DigestSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Query(sort: \Highlight.createdDate, order: .reverse) private var highlights: [Highlight]
  @Query(sort: \Note.createdDate, order: .reverse) private var notes: [Note]
  @Query private var books: [Book]
  @Query(sort: \ReadingSession.date, order: .reverse) private var sessions: [ReadingSession]

  @AppStorage("digest.email") private var email = ""
  @AppStorage("digest.daily-enabled") private var dailyEnabled = false
  @AppStorage("digest.weekly-enabled") private var weeklyEnabled = false

  @State private var isWorking = false
  @State private var didFail = false
  @State private var message: String?
  @State private var lastDaily: String?
  @State private var lastWeekly: String?

  private var emailValid: Bool {
    let clean = email.trimmingCharacters(in: .whitespacesAndNewlines)
    return clean.contains("@") && clean.split(separator: "@").last?.contains(".") == true
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(alignment: .leading, spacing: Theme.sm) {
            Text("READING RECAPS")
              .font(.caption.weight(.bold)).tracking(1.2).foregroundStyle(Theme.accentDeep)
            Text("Remember what you read")
              .font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
            Text("Inkflow sends your actual reading and listening progress, the books you moved through, and the ideas you saved.")
              .font(.subheadline).foregroundStyle(Theme.inkSoft)
          }
          .padding(.vertical, Theme.xs)
        }

        Section("Send to") {
          TextField("you@example.com", text: $email)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.emailAddress)
          if !email.isEmpty && !emailValid {
            Text("Enter a valid email address.").font(.caption).foregroundStyle(.red)
          }
        }

        Section("Schedule") {
          Toggle("Daily recap", isOn: $dailyEnabled).tint(Theme.accent)
          Text("Yesterday’s reading, listening, and saved ideas around 8:00 AM local time.")
            .font(.caption).foregroundStyle(Theme.inkSoft)
          Toggle("Weekly recap", isOn: $weeklyEnabled).tint(Theme.accent)
          Text("Your week’s most important points every Monday morning.")
            .font(.caption).foregroundStyle(Theme.inkSoft)
        }

        Section("Your local reading data") {
          LabeledContent("Saved ideas", value: "\(highlights.count + notes.count)")
          LabeledContent("Books in progress", value: "\(books.filter { $0.isStarted && !$0.isFinished }.count)")
          LabeledContent("Sessions", value: "\(sessions.count)")
          if let lastDaily { Text("Last daily recap: \(lastDaily)").font(.caption).foregroundStyle(Theme.inkSoft) }
          if let lastWeekly { Text("Last weekly recap: \(lastWeekly)").font(.caption).foregroundStyle(Theme.inkSoft) }
        }

        Section {
          Button { Task { await saveAndSync() } } label: {
            HStack {
              if isWorking { ProgressView().tint(.white) }
              Text(isWorking ? "Saving…" : "Save recap settings")
              Spacer()
            }
          }
          .buttonStyle(.borderedProminent)
          .tint(Theme.accent)
          .disabled(isWorking || !emailValid)

          Button("Send a daily sample") { Task { await sendSample() } }
            .disabled(isWorking || !emailValid)
        } footer: {
          if let message {
            Text(message).foregroundStyle(didFail ? .red : Theme.accent)
          }
        }
      }
      .navigationTitle("Reading recaps")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
      .task { await loadPreferences() }
      .scrollContentBackground(.hidden)
      .background(Theme.paper)
    }
    .__tenxTrackView("DigestSettingsView")
  }

  @MainActor
  private func loadPreferences() async {
    guard let preferences = try? await DigestSync.fetchPreferences() else { return }
    email = preferences.email
    dailyEnabled = preferences.daily_enabled
    weeklyEnabled = preferences.weekly_enabled
    lastDaily = preferences.last_daily_sent_at
    lastWeekly = preferences.last_weekly_sent_at
  }

  @MainActor
  private func saveAndSync() async {
    isWorking = true
    didFail = false
    message = nil
    do {
      let preferences = try await DigestSync.savePreferences(
        email: email, dailyEnabled: dailyEnabled, weeklyEnabled: weeklyEnabled)
      try await DigestSync.sync(highlights: highlights, notes: notes, books: books, sessions: sessions)
      lastDaily = preferences.last_daily_sent_at
      lastWeekly = preferences.last_weekly_sent_at
      message = "Recaps are saved for \(TimeZone.current.identifier)."
    } catch {
      didFail = true
      message = error.localizedDescription
    }
    isWorking = false
  }

  @MainActor
  private func sendSample() async {
    isWorking = true
    didFail = false
    message = nil
    do {
      _ = try await DigestSync.savePreferences(
        email: email, dailyEnabled: dailyEnabled, weeklyEnabled: weeklyEnabled)
      try await DigestSync.sync(highlights: highlights, notes: notes, books: books, sessions: sessions)
      try await DigestSync.sendSample(kind: "daily")
      message = "Sample email accepted. Check \(email) shortly."
    } catch {
      didFail = true
      message = error.localizedDescription
    }
    isWorking = false
  }
}
