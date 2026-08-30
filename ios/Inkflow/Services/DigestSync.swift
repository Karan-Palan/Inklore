import Foundation
import SwiftData

/// Syncs a compact, account-free mirror of local reading data for daily and
/// weekly recaps. A stable installation header scopes the data until sign-in is
/// introduced; no local book text or provider credentials leave the device.
@MainActor
struct DigestSync {
  enum SyncError: LocalizedError {
    case request(String)

    var errorDescription: String? {
      switch self {
      case .request(let message): return message
      }
    }
  }

  struct Preferences: Decodable, Sendable {
    let email: String
    let daily_enabled: Bool
    let weekly_enabled: Bool
    let timezone: String
    let last_daily_sent_at: String?
    let last_weekly_sent_at: String?
  }

  private static let backend = BackendClient()

  static func fetchPreferences() async throws -> Preferences? {
    do {
      return try await backend.get(
        Preferences.self, path: "/api/v1/digest/preferences",
        headers: InkflowInstallationIdentity.headers)
    } catch let error as TenxBackendError {
      if case .requestFailed(let status, _) = error, status == 404 { return nil }
      throw SyncError.request(error.errorDescription ?? "Could not load recap settings.")
    } catch {
      throw SyncError.request("Could not load recap settings.")
    }
  }

  static func savePreferences(
    email: String,
    dailyEnabled: Bool,
    weeklyEnabled: Bool
  ) async throws -> Preferences {
    do {
      return try await backend.send(
        Preferences.self,
        path: "/api/v1/digest/preferences",
        body: PreferencesBody(
          email: email.trimmingCharacters(in: .whitespacesAndNewlines),
          daily_enabled: dailyEnabled, weekly_enabled: weeklyEnabled,
          timezone: TimeZone.current.identifier),
        headers: InkflowInstallationIdentity.headers)
    } catch let error as TenxBackendError {
      throw SyncError.request(error.errorDescription ?? "Could not save recap settings.")
    } catch {
      throw SyncError.request("Could not save recap settings.")
    }
  }

  static func sync(
    highlights: [Highlight], notes: [Note], books: [Book], sessions: [ReadingSession]
  ) async throws {
    do {
      _ = try await backend.send(
        path: "/api/v1/digest/sync",
        body: SyncBody(
          notes: makeNoteRows(highlights: highlights, notes: notes),
          books: makeBookRows(books: books),
          activity: makeActivityRows(sessions: sessions)),
        headers: InkflowInstallationIdentity.headers)
    } catch let error as TenxBackendError {
      throw SyncError.request(error.errorDescription ?? "Could not sync your reading recap.")
    } catch {
      throw SyncError.request("Could not sync your reading recap.")
    }
  }

  static func sendSample(kind: String) async throws {
    do {
      _ = try await backend.send(
        path: "/api/v1/digest/send-sample",
        body: EmptyBody(),
        queryItems: [URLQueryItem(name: "kind", value: kind)],
        headers: InkflowInstallationIdentity.headers)
    } catch let error as TenxBackendError {
      throw SyncError.request(error.errorDescription ?? "Could not send the sample recap.")
    } catch {
      throw SyncError.request("Could not send the sample recap.")
    }
  }

  private static func makeNoteRows(highlights: [Highlight], notes: [Note]) -> [DigestNoteRow] {
    let formatter = ISO8601DateFormatter()
    var rows: [DigestNoteRow] = highlights.map { highlight in
      DigestNoteRow(
        id: highlight.id.uuidString, kind: "highlight", book_title: highlight.book?.title ?? "",
        chapter: highlight.chapterTitle, passage: highlight.text, body: "",
        created_at: formatter.string(from: highlight.createdDate))
    }
    rows += notes.map { note in
      DigestNoteRow(
        id: note.id.uuidString, kind: "note", book_title: note.book?.title ?? "",
        chapter: note.chapterTitle, passage: note.passage, body: note.body,
        created_at: formatter.string(from: note.createdDate))
    }
    return rows
  }

  private static func makeBookRows(books: [Book]) -> [DigestBookRow] {
    let formatter = ISO8601DateFormatter()
    return books.prefix(20).map { book in
      let chapter = ChapterSummaryContent.section(for: book, offset: book.canonicalCharacterOffset)?.title ?? ""
      return DigestBookRow(
        id: book.id.uuidString, title: book.title, author: book.author,
        excerpt: String(book.bodyText.prefix(4000)), is_active: book.isStarted && !book.isFinished,
        progress: book.progress, current_chapter: chapter,
        last_read_at: book.lastOpenedDate.map { formatter.string(from: $0) })
    }
  }

  private static func makeActivityRows(sessions: [ReadingSession]) -> [DigestActivityRow] {
    var buckets: [Date: (read: Int, listen: Int, pages: Int)] = [:]
    let calendar = Calendar.current
    for session in sessions {
      let day = calendar.startOfDay(for: session.date)
      var total = buckets[day] ?? (0, 0, 0)
      if session.wasListening { total.listen += session.minutes } else { total.read += session.minutes }
      total.pages += session.pagesRead
      buckets[day] = total
    }
    let dayFormatter = ISO8601DateFormatter()
    dayFormatter.formatOptions = [.withFullDate]
    return buckets.keys.sorted().suffix(90).map { day in
      let total = buckets[day] ?? (0, 0, 0)
      return DigestActivityRow(
        date: dayFormatter.string(from: day), read_minutes: total.read,
        listen_minutes: total.listen, pages_read: total.pages)
    }
  }
}

private struct PreferencesBody: Encodable {
  let email: String
  let daily_enabled: Bool
  let weekly_enabled: Bool
  let timezone: String
}

private struct SyncBody: Encodable {
  let notes: [DigestNoteRow]
  let books: [DigestBookRow]
  let activity: [DigestActivityRow]
}

private struct DigestNoteRow: Encodable {
  let id: String
  let kind: String
  let book_title: String
  let chapter: String
  let passage: String
  let body: String
  let created_at: String
}

private struct DigestBookRow: Encodable {
  let id: String
  let title: String
  let author: String
  let excerpt: String
  let is_active: Bool
  let progress: Double
  let current_chapter: String
  let last_read_at: String?
}

private struct DigestActivityRow: Encodable {
  let date: String
  let read_minutes: Int
  let listen_minutes: Int
  let pages_read: Int
}

private struct EmptyBody: Encodable {}
