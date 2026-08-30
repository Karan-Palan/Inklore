import Foundation

/// Extracts readable text and basic metadata from a Word OpenXML (`.docx`)
/// document. DOCX files are ZIP containers, so this deliberately shares the
/// EPUB archive reader and never uploads a user's document to a server.
enum DocxDocument {
  struct Result {
    let title: String?
    let author: String?
    let text: String
  }

  static func parse(_ data: Data) throws -> Result {
    let entries = try EpubArchive.readEntries(from: data)
    guard let document = entries.first(where: { $0.path == "word/document.xml" }) else {
      throw BookImporter.ImportError.unreadable
    }

    let body = BodyHandler()
    let bodyParser = XMLParser(data: document.data)
    bodyParser.delegate = body
    guard bodyParser.parse() else { throw BookImporter.ImportError.unreadable }

    var title: String?
    var author: String?
    if let core = entries.first(where: { $0.path == "docProps/core.xml" }) {
      let metadata = MetadataHandler()
      let parser = XMLParser(data: core.data)
      parser.delegate = metadata
      if parser.parse() {
        title = metadata.title
        author = metadata.author
      }
    }

    let text = body.paragraphs
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw BookImporter.ImportError.unreadable }
    return Result(title: title, author: author, text: text)
  }

  private final class BodyHandler: NSObject, XMLParserDelegate {
    var paragraphs: [String] = []
    private var paragraph = ""
    private var runText = ""
    private var isReadingText = false

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      switch localName(elementName) {
      case "p": paragraph = ""
      case "t":
        runText = ""
        isReadingText = true
      case "tab": paragraph += "\t"
      case "br", "cr": paragraph += "\n"
      default: break
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if isReadingText { runText += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      switch localName(elementName) {
      case "t":
        paragraph += runText
        runText = ""
        isReadingText = false
      case "p":
        let clean = paragraph
          .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { paragraphs.append(clean) }
        paragraph = ""
      default: break
      }
    }
  }

  private final class MetadataHandler: NSObject, XMLParserDelegate {
    var title: String?
    var author: String?
    private var field: String?
    private var value = ""

    func parser(
      _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]
    ) {
      let name = localName(elementName)
      if name == "title" || name == "creator" {
        field = name
        value = ""
      }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      if field != nil { value += string }
    }

    func parser(
      _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
      qualifiedName qName: String?
    ) {
      let name = localName(elementName)
      guard name == field else { return }
      let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
      if name == "title", !clean.isEmpty { title = clean }
      if name == "creator", !clean.isEmpty { author = clean }
      field = nil
    }
  }

  private static func localName(_ qualified: String) -> String {
    qualified.split(separator: ":").last.map(String.init)?.lowercased() ?? qualified.lowercased()
  }
}
