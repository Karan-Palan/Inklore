import SwiftData
import SwiftUI

/// Cloud Backups — a real `TenxStorage` flow. The user exports their highlights
/// and notes (generated in-app), uploads them to the private R2 `attachments`
/// bucket, and can restore (download + preview) or delete past backups.
struct BackupsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AuthStore.self) private var auth
  @Query(sort: \Highlight.createdDate, order: .reverse) private var highlights: [Highlight]
  @Query(sort: \Note.createdDate, order: .reverse) private var notes: [Note]

  @State private var objects: [TenxStorageObject] = []
  @State private var isLoading = false
  @State private var isBackingUp = false
  @State private var errorMessage: String?
  @State private var successMessage: String?
  @State private var previewText: String?
  @State private var previewingID: String?
  @State private var didLoadOnce = false

  private var itemCount: Int { highlights.count + notes.count }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: Theme.md) {
            HStack(spacing: Theme.sm) {
              Image(systemName: "icloud.and.arrow.up.fill")
                .font(.title2).foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .background(Theme.accent.opacity(0.12), in: Circle())
              Text("PRIVATE CLOUD COPY")
                .font(.caption.weight(.bold))
                .tracking(1)
                .foregroundStyle(Theme.inkFaint)
            }
            Text("Back up your reading trail")
              .font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
            Text(
              "Save a private text copy of your \(itemCount) highlights and notes. You can open any backup here whenever you need to revisit it."
            )
            .font(.subheadline).foregroundStyle(Theme.inkSoft)
          }
          .padding(.vertical, Theme.xs)
        }

        Section {
          Button {
            Task { await backUpNow() }
          } label: {
            HStack(spacing: Theme.sm) {
              if isBackingUp {
                ProgressView().tint(.white)
                Text("Creating your backup…")
              } else {
                Label("Back up now", systemImage: "arrow.up.to.line")
              }
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .tint(Theme.accent)
          .disabled(isBackingUp)
        } footer: {
          if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
              .foregroundStyle(.red)
          } else if let successMessage {
            Label(successMessage, systemImage: "checkmark.circle.fill")
              .foregroundStyle(Theme.accent)
          } else {
            Text("Backups include your saved highlights and notes; books themselves stay on this device.")
          }
        }

        Section("Your backups") {
          if isLoading {
            VStack(spacing: Theme.sm) {
              ProgressView().tint(Theme.accent)
              Text("Checking your cloud copies…")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.md)
          } else if objects.isEmpty {
            VStack(spacing: Theme.sm) {
              Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(Theme.inkFaint)
              Text("No cloud copies yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
              Text("Make a backup whenever you want a safe snapshot of your saved ideas.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.md)
          } else {
            ForEach(objects) { object in
              Button {
                Task { await preview(object) }
              } label: {
                HStack(spacing: Theme.md) {
                  Image(systemName: "doc.text.fill")
                    .foregroundStyle(Theme.accent)
                    .frame(width: 38, height: 38)
                    .background(Theme.accent.opacity(0.1), in: Circle())
                  VStack(alignment: .leading, spacing: 2) {
                    Text(object.filename ?? "Backup")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(Theme.ink)
                      .lineLimit(1)
                    Text("Text backup · \(sizeLabel(object.sizeBytes))")
                      .font(.caption).foregroundStyle(Theme.inkFaint)
                  }
                  Spacer()
                  if previewingID == object.id {
                    ProgressView().tint(Theme.accent)
                  } else {
                    Image(systemName: "chevron.right")
                      .font(.footnote.weight(.semibold))
                      .foregroundStyle(Theme.inkFaint)
                  }
                }
              }
              .buttonStyle(.plain)
              .swipeActions {
                Button(role: .destructive) {
                  Task { await delete(object) }
                } label: {
                  Label("Delete", systemImage: "trash")
                }
              }
            }
          }
        }
      }
      .navigationTitle("Cloud Backups")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
      .task {
        guard !didLoadOnce else { return }
        didLoadOnce = true
        await load()
      }
      .scrollContentBackground(.hidden)
      .background(Theme.paper)
      .sheet(
        isPresented: Binding(get: { previewText != nil }, set: { if !$0 { previewText = nil } })
      ) {
        BackupPreviewSheet(text: previewText ?? "")
      }
    }
    .__tenxTrackView("BackupsView")
  }

  // MARK: - Actions

  private func load() async {
    guard let token = await auth.validAccessToken() else {
      errorMessage = BackupService.BackupError.notSignedIn.errorDescription
      return
    }
    isLoading = true
    errorMessage = nil
    do {
      objects = try await BackupService.listBackups(accessToken: token)
    } catch {
      errorMessage = error.localizedDescription
    }
    isLoading = false
  }

  private func backUpNow() async {
    guard !isBackingUp else { return }
    isBackingUp = true
    errorMessage = nil
    successMessage = nil
    guard let token = await auth.validAccessToken() else {
      errorMessage = BackupService.BackupError.notSignedIn.errorDescription
      isBackingUp = false
      return
    }
    do {
      _ = try await BackupService.backupNotes(
        highlights: highlights, notes: notes, accessToken: token)
      objects = try await BackupService.listBackups(accessToken: token)
      successMessage = "Backup complete. Your reading trail is safely stored."
      UINotificationFeedbackGenerator().notificationOccurred(.success)
    } catch {
      errorMessage = error.localizedDescription
    }
    isBackingUp = false
  }

  private func preview(_ object: TenxStorageObject) async {
    guard let token = await auth.validAccessToken() else {
      errorMessage = BackupService.BackupError.notSignedIn.errorDescription
      return
    }
    previewingID = object.id
    errorMessage = nil
    defer { previewingID = nil }
    do {
      previewText = try await BackupService.downloadText(objectID: object.id, accessToken: token)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func delete(_ object: TenxStorageObject) async {
    guard let token = await auth.validAccessToken() else { return }
    do {
      try await BackupService.deleteBackup(objectID: object.id, accessToken: token)
      objects = try await BackupService.listBackups(accessToken: token)
      successMessage = "Backup deleted."
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func sizeLabel(_ bytes: Int?) -> String {
    guard let bytes else { return "Backup" }
    let kb = Double(bytes) / 1024
    return kb < 1 ? "\(bytes) bytes" : String(format: "%.0f KB", kb)
  }
}

/// Read-only preview of a downloaded backup's text.
private struct BackupPreviewSheet: View {
  @Environment(\.dismiss) private var dismiss
  let text: String

  var body: some View {
    NavigationStack {
      ScrollView {
        Text(text.isEmpty ? "This backup is empty." : text)
          .font(.system(.footnote, design: .monospaced))
          .foregroundStyle(Theme.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(Theme.lg)
      }
      .background(Theme.paper)
      .navigationTitle("Restored backup")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button("Done") { dismiss() }
        }
      }
    }
  }
}

#Preview {
  BackupsView()
    .environment(AuthStore())
    .modelContainer(PreviewData.container)
}
