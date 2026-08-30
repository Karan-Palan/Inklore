import SwiftData
import SwiftUI

/// Settings for the once-a-day notes email. The user enters an email and toggles
/// the daily digest on. When they have highlights/notes, the email contains them;
/// when they don't, the backend generates 5-10 AI study notes from their active
/// books. The test action syncs current data and triggers a sample email.
struct DigestSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AuthStore.self) var auth
  @Query(sort: \Highlight.createdDate, order: .reverse) private var highlights: [Highlight]
  @Query(sort: \Note.createdDate, order: .reverse) private var notes: [Note]
  @Query private var books: [Book]

  @AppStorage("digest.email") var email = ""
  @AppStorage("digest.enabled") var enabled = false

  @State private var isWorking = false
  @State private var didFail = false
  @State private var message: String?
  @State var syncedStatus: String?

  private var noteCount: Int { highlights.count + notes.count }
  private var activeBooks: Int { books.filter { $0.isStarted && !$0.isFinished }.count }
  private var emailValid: Bool {
    let trimmed = email.trimmingCharacters(in: .whitespaces)
    return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 5
  }

  var body: some View {
    Group {
      NavigationStack {
        Form {
          Section {
            VStack(alignment: .leading, spacing: Theme.sm) {
              Image(systemName: "envelope.badge.fill")
                .font(.system(size: 30)).foregroundStyle(Theme.accent)
              Text("Your highlights, every morning")
                .font(.headline).foregroundStyle(Theme.ink)
              Text(
                "Each day we email the highlights and notes you've saved. None saved yet? We'll send 5–10 fresh study notes drawn from the books you're reading."
              )
              .font(.subheadline).foregroundStyle(Theme.inkSoft)
            }
            .padding(.vertical, 4)
          }

          Section("Send to") {
            TextField("you@example.com", text: $email)
              .textInputAutocapitalization(.never)
              .autocorrectionDisabled()
              .keyboardType(.emailAddress)
            if !email.isEmpty && !emailValid {
              Text("Enter a valid email address.")
                .font(.caption).foregroundStyle(.red)
            }
          }

          Section {
            Toggle("Daily email", isOn: $enabled)
              .tint(Theme.accent)
              .onChange(of: enabled) { _, _ in persist() }
          } footer: {
            Text("Delivered every morning around 8:00 AM.")
          }

          Section("In your next email") {
            LabeledContent("Saved notes", value: "\(noteCount)")
            LabeledContent("Books in progress", value: "\(activeBooks)")
            if noteCount == 0 {
              Text("No saved notes — we'll generate study notes from your books instead.")
                .font(.caption).foregroundStyle(Theme.inkSoft)
            }
            if let syncedStatus {
              Label(syncedStatus, systemImage: "checkmark.icloud")
                .font(.caption).foregroundStyle(Theme.accent)
            }
          }

          Section {
            Button {
              Task { await sendTest() }
            } label: {
              HStack {
                Label("Send a sample email now", systemImage: "paperplane.fill")
                Spacer()
                if isWorking { ProgressView() }
              }
            }
            .disabled(!emailValid || isWorking)
          } footer: {
            if let message {
              Label(message, systemImage: didFail ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.caption)
                .foregroundStyle(didFail ? .red : Theme.accent)
            } else if !BackendConfig.isDataReady {
              Text(
                "Your settings are saved and will activate once the backend finishes setting up."
              )
            }
          }
        }
        .navigationTitle("Daily notes email")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
          if email.isEmpty, let userEmail = auth.user?.email, !userEmail.isEmpty {
            email = userEmail
          }
        }
        .task { await loadSyncedPreferences() }
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button("Done") {
              persist()
              dismiss()
            }
          }
        }
      }
    }
    .__tenxTrackView("DigestSettingsView")
  }

  private func persist() {
    guard emailValid || !enabled else { return }
    Task {
      guard let ownerID = auth.user?.id, let token = await auth.validAccessToken() else { return }
      if let row = try? await DigestSync.savePreferences(
        email: email.trimmingCharacters(in: .whitespaces), enabled: enabled,
        ownerID: ownerID, accessToken: token)
      {
        applySyncedPreferences(row)
      }
    }
  }

  private func sendTest() async {
    isWorking = true
    didFail = false
    message = nil
    do {
      guard let ownerID = auth.user?.id, let token = await auth.validAccessToken() else {
        throw DigestSync.SyncError.notConfigured
      }
      try await DigestSync.sendNow(
        highlights: highlights, notes: notes, books: books,
        email: email.trimmingCharacters(in: .whitespaces),
        ownerID: ownerID, accessToken: token)
      message = "Sample email sent. Check \(email) in a minute (and your spam folder)."
      enabled = true
    } catch {
      didFail = true
      message = error.localizedDescription
    }
    isWorking = false
  }
}

#Preview {
  DigestSettingsView()
    .environment(AuthStore())
    .modelContainer(PreviewData.container)
}
