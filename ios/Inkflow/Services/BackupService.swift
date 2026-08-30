import Foundation

/// Real cloud-backup service backed by 10x App Services storage (`TenxStorage`,
/// R2). Generates a plain-text export of the user's highlights and notes in-app
/// and uploads those bytes to the private `attachments` bucket, then lists,
/// downloads, and deletes backups. All calls are owner-scoped via the signed-in
/// access token.
@MainActor
struct BackupService {
  enum BackupError: LocalizedError {
    case notSignedIn
    case request(String)

    var errorDescription: String? {
      switch self {
      case .notSignedIn:
        return "Sign in to back up your notes to the cloud."
      case .request(let message):
        return message
      }
    }
  }

  static let bucket = "attachments"
  private static let storage = TenxStorage()

  /// Builds a readable text export of the user's highlights and notes.
  static func makeExport(highlights: [Highlight], notes: [Note]) -> Data {
    var lines: [String] = []
    lines.append("Inkflow — Notes & Highlights backup")
    lines.append("Exported \(ISO8601DateFormatter().string(from: .now))")
    lines.append("")

    if highlights.isEmpty && notes.isEmpty {
      lines.append("No highlights or notes saved yet.")
    }

    if !highlights.isEmpty {
      lines.append("HIGHLIGHTS (\(highlights.count))")
      lines.append("")
      for h in highlights {
        lines.append("• \(h.book?.title ?? "Unknown book") — \(h.chapterTitle)")
        lines.append("  \"\(h.text)\"")
        lines.append("")
      }
    }

    if !notes.isEmpty {
      lines.append("NOTES (\(notes.count))")
      lines.append("")
      for n in notes {
        lines.append("• \(n.book?.title ?? "Unknown book") — \(n.chapterTitle)")
        if !n.passage.isEmpty { lines.append("  \"\(n.passage)\"") }
        lines.append("  \(n.body)")
        lines.append("")
      }
    }

    return Data(lines.joined(separator: "\n").utf8)
  }

  /// Uploads a notes/highlights export to the private attachments bucket.
  @discardableResult
  static func backupNotes(
    highlights: [Highlight], notes: [Note], accessToken: String
  ) async throws -> TenxStorageObject {
    let data = makeExport(highlights: highlights, notes: notes)
    let stamp = Self.fileStamp()
    do {
      return try await storage.upload(
        data: data,
        bucket: bucket,
        filename: "inkflow-notes-\(stamp).txt",
        contentType: "text/plain",
        accessToken: accessToken)
    } catch {
      throw BackupError.request(error.localizedDescription)
    }
  }

  /// Lists the current backups for the signed-in user.
  static func listBackups(accessToken: String) async throws -> [TenxStorageObject] {
    do {
      return try await storage.listObjects(bucket: bucket, accessToken: accessToken)
    } catch {
      throw BackupError.request(error.localizedDescription)
    }
  }

  /// Downloads a backup's text contents.
  static func downloadText(objectID: String, accessToken: String) async throws -> String {
    do {
      let data = try await storage.download(objectID: objectID, accessToken: accessToken)
      return String(data: data, encoding: .utf8) ?? ""
    } catch {
      throw BackupError.request(error.localizedDescription)
    }
  }

  /// Permanently removes a backup.
  static func deleteBackup(objectID: String, accessToken: String) async throws {
    do {
      _ = try await storage.deleteObject(objectID: objectID, accessToken: accessToken)
    } catch {
      throw BackupError.request(error.localizedDescription)
    }
  }

  private static func fileStamp() -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    return f.string(from: .now)
  }
}
