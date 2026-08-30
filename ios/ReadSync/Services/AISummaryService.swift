import Foundation

/// Server-backed summary generation. Provider credentials and model routing
/// remain in the backend; the app sends only the text the reader explicitly
/// chooses to summarize.
enum AISummaryService {
  enum Scope: String, Encodable { case chapter, book }

  enum ServiceError: LocalizedError {
    case emptyText
    case request(String)

    var errorDescription: String? {
      switch self {
      case .emptyText: return "There isn't enough extractable text to summarize."
      case .request(let message): return message
      }
    }
  }

  struct Result: Decodable {
    let markdown: String
    let model: String
    let reasoning_effort: String
  }

  private struct SummaryBody: Encodable {
    let book_title: String
    let author: String
    let section_title: String
    let scope: Scope
    let text: String
  }

  private static let backend = BackendClient()

  static func generate(
    book: Book, sectionTitle: String, text: String, scope: Scope
  ) async throws -> Result {
    // Do not trim/copy an entire book just to send the bounded summary input.
    // `prefix` caps the work and payload before normalization.
    let clean = String(text.prefix(60_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 80 else { throw ServiceError.emptyText }
    do {
      return try await backend.send(
        Result.self,
        path: "/api/v1/summaries",
        body: SummaryBody(
          book_title: book.title, author: book.author,
          section_title: sectionTitle, scope: scope, text: clean))
    } catch let error as TenxBackendError {
      throw ServiceError.request(
        error.errorDescription ?? "The AI summary service isn't ready yet.")
    } catch {
      throw ServiceError.request("The AI summary service isn't ready yet. Your local summary is still available.")
    }
  }
}

/// Asynchronous video-summary API. Generation is durable on the backend and
/// does not rely on a long-lived mobile request.
enum VideoSummaryService {
  struct Scene: Decodable, Identifiable {
    var id: Int { position }
    let position: Int
    let title: String
    let narration: String
    let duration_seconds: Int
    let status: String
    let content_url: String?
  }

  struct Job: Decodable {
    let id: UUID
    let status: String
    let title: String?
    let aspect_ratio: String?
    let duration_seconds: Int?
    let completed_scenes: Int
    let total_scenes: Int
    let error_message: String?
    let scenes: [Scene]
  }

  enum ServiceError: LocalizedError {
    case emptyText, request(String)
    var errorDescription: String? {
      switch self {
      case .emptyText: return "There isn't enough extractable text to create a video."
      case .request(let message): return message
      }
    }
  }

  private struct CreateBody: Encodable {
    let book_id: String
    let book_title: String
    let author: String
    let text: String
  }

  private static let backend = BackendClient()

  static func create(book: Book, accessToken: String) async throws -> Job {
    let text = String(book.bodyText.prefix(200_000))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 200 else { throw ServiceError.emptyText }
    do {
      return try await backend.send(
        Job.self, path: "/api/v1/video-summaries",
        body: CreateBody(book_id: book.id.uuidString, book_title: book.title,
                         author: book.author, text: text),
        accessToken: accessToken)
    } catch let error as TenxBackendError {
      throw ServiceError.request(error.errorDescription ?? "Could not start video generation.")
    } catch {
      throw ServiceError.request("Could not start video generation.")
    }
  }

  static func status(id: UUID, accessToken: String) async throws -> Job {
    do {
      return try await backend.get(
        Job.self, path: "/api/v1/video-summaries/\(id.uuidString)",
        accessToken: accessToken)
    } catch {
      throw ServiceError.request("Could not refresh video generation.")
    }
  }
}
