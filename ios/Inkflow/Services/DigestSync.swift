import Foundation
import SwiftData

/// Drives the daily-digest backend. All database writes happen server-side
/// (the managed data REST API is read-only for these tables), so this type just
/// posts the user's current local highlights/notes + active books to the
/// backend runtime, which persists them in Neon and sends the email.
@MainActor
struct DigestSync {
  enum SyncError: LocalizedError {
    case notConfigured
    case request(String)

    var errorDescription: String? {
      switch self {
      case .notConfigured:
        return "Sign in and wait for the backend to finish setting up to enable the daily email."
      case .request(let message):
        return message
      }
    }
  }

  private static let backend = BackendClient()
  private static let data = TenxData()

  // MARK: - Preferences

  /// Save the recipient's email + enabled flag for the signed-in user, then read
  /// the persisted row back through the managed Data API to confirm the
  /// server-side write landed (the backend runtime owns the write; the app
  /// verifies it via owner-scoped RLS read).
  @discardableResult
  static func savePreferences(
    email: String, enabled: Bool, ownerID: String, accessToken: String
  ) async throws -> DigestSubscriberRow? {
    try await call(
      path: "/api/v1/digest/preferences",
      body: PreferencesBody(email: email, enabled: enabled),
      accessToken: accessToken)
    return try await fetchSubscriber(ownerID: ownerID, accessToken: accessToken)
  }

  /// Read the signed-in user's persisted digest subscription from Neon via the
  /// managed Data API. Returns nil when no row exists yet.
  static func fetchSubscriber(ownerID: String, accessToken: String) async throws
    -> DigestSubscriberRow?
  {
    guard BackendConfig.isDataReady else { return nil }
    do {
      let raw = try await data.select(
        table: "digest_subscribers",
        queryItems: [
          URLQueryItem(name: "owner_id", value: "eq.\(ownerID)"),
          URLQueryItem(name: "select", value: "owner_id,email,enabled,last_sent_at"),
          URLQueryItem(name: "limit", value: "1"),
        ],
        accessToken: accessToken)
      let rows = try JSONDecoder().decode([DigestSubscriberRow].self, from: raw)
      return rows.first
    } catch let error as TenxBackendError {
      throw SyncError.request(error.errorDescription ?? "The request failed.")
    } catch is DecodingError {
      return nil
    } catch {
      throw SyncError.request(error.localizedDescription)
    }
  }

  // MARK: - Send

  /// Sync current local data to the backend and trigger an immediate send.
  static func sendNow(
    highlights: [Highlight], notes: [Note], books: [Book],
    email: String, ownerID: String, accessToken: String
  ) async throws {
    let noteRows = makeNoteRows(highlights: highlights, notes: notes)
    let bookRows = makeBookRows(books: books)
    try await call(
      path: "/api/v1/daily-digest",
      body: DigestBody(
        email: email, enabled: true, force: true, notes: noteRows, books: bookRows),
      accessToken: accessToken)
  }

  // MARK: - Helpers

  private static func makeNoteRows(highlights: [Highlight], notes: [Note]) -> [DigestNoteRow] {
    var rows: [DigestNoteRow] = []
    for h in highlights {
      rows.append(
        DigestNoteRow(
          id: h.id.uuidString, kind: "highlight",
          book_title: h.book?.title ?? "", chapter: h.chapterTitle,
          passage: h.text, body: "",
          created_at: ISO8601DateFormatter().string(from: h.createdDate)))
    }
    for n in notes {
      rows.append(
        DigestNoteRow(
          id: n.id.uuidString, kind: "note",
          book_title: n.book?.title ?? "", chapter: n.chapterTitle,
          passage: n.passage, body: n.body,
          created_at: ISO8601DateFormatter().string(from: n.createdDate)))
    }
    return rows
  }

  private static func makeBookRows(books: [Book]) -> [DigestBookRow] {
    let active = books.filter { $0.isStarted && !$0.isFinished }
    return active.prefix(20).map { book in
      DigestBookRow(
        id: book.id.uuidString, title: book.title, author: book.author,
        excerpt: String(book.bodyText.prefix(4000)))
    }
  }

  private static func call<T: Encodable>(path: String, body: T, accessToken: String) async throws {
    guard BackendConfig.isAuthReady else { throw SyncError.notConfigured }
    do {
      _ = try await backend.send(path: path, body: body, accessToken: accessToken)
    } catch let error as TenxBackendError {
      throw SyncError.request(error.errorDescription ?? "The request failed.")
    } catch {
      throw SyncError.request(error.localizedDescription)
    }
  }
}

// MARK: - Decoded rows

/// One row from the managed `digest_subscribers` table (read via `TenxData`).
struct DigestSubscriberRow: Decodable, Sendable {
  let owner_id: String
  let email: String
  let enabled: Bool
  let last_sent_at: String?
}

// MARK: - Request payloads

private struct PreferencesBody: Encodable {
  let email: String
  let enabled: Bool
}

private struct DigestBody: Encodable {
  let email: String
  let enabled: Bool
  let force: Bool
  let notes: [DigestNoteRow]
  let books: [DigestBookRow]
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
}
