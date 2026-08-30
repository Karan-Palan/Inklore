import Foundation

/// Server-backed summary generation. Provider credentials and model routing
/// remain in the backend; the app sends only the text the reader explicitly
/// chooses to summarize.
enum AISummaryService {
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
    let text: String
  }

  private static let backend = BackendClient()

  static func generate(book: Book, sectionTitle: String, text: String) async throws -> Result {
    // One chapter is enough for this deliberately concise output. Bounding the
    // excerpt keeps the request fast and ensures a whole book is never sent.
    let clean = String(text.prefix(40_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count >= 80 else { throw ServiceError.emptyText }
    do {
      return try await backend.send(
        Result.self,
        path: "/api/v1/summaries",
        body: SummaryBody(
          book_title: book.title, author: book.author,
          section_title: sectionTitle, text: clean))
    } catch let error as TenxBackendError {
      throw ServiceError.request(
        error.errorDescription ?? "The AI summary service isn't ready yet.")
    } catch {
      throw ServiceError.request("The AI summary service isn't ready yet. Your local chapter summary is still available.")
    }
  }
}

/// A durable chapter-video job lives on the server. The app never sends a
/// provider key; an installation UUID scopes jobs until account sync ships.
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
    let chapter_id: String
    let chapter_title: String
    let title: String?
    let aspect_ratio: String?
    let duration_seconds: Int?
    let completed_scenes: Int
    let total_scenes: Int
    let error_message: String?
    let provider_status_code: Int?
    let scenes: [Scene]
  }

  enum ServiceError: LocalizedError {
    case emptyText
    case request(String)

    var errorDescription: String? {
      switch self {
      case .emptyText: return "This chapter does not have enough extractable text for a video yet."
      case .request(let message): return message
      }
    }
  }

  private struct CreateBody: Encodable {
    let book_id: String
    let book_title: String
    let author: String
    let chapter_id: String
    let chapter_title: String
    let text: String
  }

  private static let backend = BackendClient()

  static func create(book: Book, chapter: ChapterSummarySection) async throws -> Job {
    let source = String(chapter.text.prefix(60_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    guard source.count >= 200 else { throw ServiceError.emptyText }
    do {
      return try await backend.send(
        Job.self,
        path: "/api/v1/video-summaries",
        body: CreateBody(
          book_id: book.id.uuidString, book_title: book.title, author: book.author,
          chapter_id: chapter.id, chapter_title: chapter.title, text: source),
        headers: InkflowInstallationIdentity.headers)
    } catch let error as TenxBackendError {
      throw ServiceError.request(error.errorDescription ?? "Video generation could not be started.")
    } catch {
      throw ServiceError.request("Video generation could not be started. Please try again.")
    }
  }

  static func status(id: UUID) async throws -> Job {
    do {
      return try await backend.get(
        Job.self, path: "/api/v1/video-summaries/\(id.uuidString)",
        headers: InkflowInstallationIdentity.headers)
    } catch let error as TenxBackendError {
      throw ServiceError.request(error.errorDescription ?? "Video progress could not be refreshed.")
    } catch {
      throw ServiceError.request("Video progress could not be refreshed.")
    }
  }
}

/// Stable per-installation identity used only until sign-in/sync is introduced.
/// It is not a credential and never represents an arbitrary server owner id.
enum InkflowInstallationIdentity {
  private static let key = "inkflow.installation-id"

  static var value: String {
    if let saved = UserDefaults.standard.string(forKey: key), UUID(uuidString: saved) != nil {
      return saved
    }
    let fresh = UUID().uuidString.lowercased()
    UserDefaults.standard.set(fresh, forKey: key)
    return fresh
  }

  static var headers: [String: String] { ["X-Inkflow-Installation-ID": value] }
}
