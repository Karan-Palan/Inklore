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
  @State private var previewText: String?
  @State private var didLoadOnce = false

  private var itemCount: Int { highlights.count + notes.count }

  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(alignment: .leading, spacing: Theme.sm) {
            Image(systemName: "icloud.and.arrow.up.fill")
              .font(.system(size: 30)).foregroundStyle(Theme.accent)
            Text("Back up your notes")
              .font(.headline).foregroundStyle(Theme.ink)
            Text(
              "Save a copy of your \(itemCount) highlights and notes to secure cloud storage. Restore them any time."
            )
            .font(.subheadline).foregroundStyle(Theme.inkSoft)
          }
          .padding(.vertical, 4)
        }

        Section {
          Button {
            Task { await backUpNow() }
          } label: {
            HStack {
              Label("Back up now", systemImage: "arrow.up.to.line")
              Spacer()
              if isBackingUp { ProgressView() }
            }
          }
          .disabled(isBackingUp)
        } footer: {
          if let errorMessage {
            Text(errorMessage).foregroundStyle(.red)
          }
        }

        Section("Your backups") {
          if isLoading {
            HStack {
              Spacer()
              ProgressView()
              Spacer()
            }
          } else if objects.isEmpty {
            Text("No backups yet. Tap “Back up now” to create one.")
              .font(.subheadline).foregroundStyle(Theme.inkSoft)
          } else {
            ForEach(objects) { object in
              Button {
                Task { await preview(object) }
              } label: {
                HStack(spacing: Theme.md) {
                  Image(systemName: "doc.text.fill")
                    .foregroundStyle(Theme.accent)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(object.filename ?? "Backup")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(Theme.ink)
                      .lineLimit(1)
                    Text(sizeLabel(object.sizeBytes))
                      .font(.caption).foregroundStyle(Theme.inkFaint)
                  }
                  Spacer()
                  Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Theme.inkFaint)
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
    guard let token = await auth.validAccessToken() else {
      errorMessage = BackupService.BackupError.notSignedIn.errorDescription
      isBackingUp = false
      return
    }
    do {
      _ = try await BackupService.backupNotes(
        highlights: highlights, notes: notes, accessToken: token)
      objects = try await BackupService.listBackups(accessToken: token)
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
