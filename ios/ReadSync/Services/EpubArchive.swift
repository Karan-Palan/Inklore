import Compression
import Foundation

/// A tiny, dependency-free ZIP reader good enough for EPUB files. It parses the
/// central directory, then inflates each entry (stored or DEFLATE) using Apple's
/// Compression framework. Used to extract a downloaded `.epub` into a folder of
/// real HTML/CSS/image files that a `WKWebView` can render with full fidelity.
enum EpubArchive {

  enum ArchiveError: LocalizedError {
    case notZip
    case corrupt
    case tooLarge
    case writeFailed

    var errorDescription: String? {
      switch self {
      case .notZip: return "This file isn't a valid EPUB."
      case .corrupt: return "The EPUB file is damaged or incomplete."
      case .tooLarge: return "This EPUB is too large to import safely on this device."
      case .writeFailed: return "Couldn't save the book to your device."
      }
    }
  }

  struct Entry {
    let path: String
    let data: Data
  }

  // These limits prevent forged ZIP headers from allocating gigabytes (a ZIP
  // bomb). They still leave room for image-heavy public-domain EPUBs.
  static let maximumArchiveBytes = 80 * 1024 * 1024
  private static let maximumEntryCount = 5_000
  private static let maximumEntryBytes = 32 * 1024 * 1024
  private static let maximumExpandedBytes = 180 * 1024 * 1024

  /// Root directory where extracted EPUBs live.
  static var storeURL: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let url = base.appendingPathComponent("Epubs", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static func folderURL(named name: String) -> URL {
    storeURL.appendingPathComponent(name, isDirectory: true)
  }

  /// Extracts the EPUB `data` into a fresh uniquely-named folder under the store
  /// and returns the folder name. Throws if the archive is unreadable.
  static func extract(_ data: Data) throws -> String {
    let entries = try readEntries(from: data)
    guard !entries.isEmpty else { throw ArchiveError.corrupt }

    let folderName = UUID().uuidString
    let root = folderURL(named: folderName)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    var completed = false
    defer {
      if !completed { try? FileManager.default.removeItem(at: root) }
    }

    for entry in entries where !entry.path.hasSuffix("/") {
      // Normalize and guard against traversal and absolute paths. Resolving the
      // path before writing keeps crafted archives inside the EPUB store.
      let clean = entry.path.replacingOccurrences(of: "\\", with: "/")
      guard !clean.hasPrefix("/"), !clean.contains("..") else { continue }
      let dest = root.appendingPathComponent(clean).standardizedFileURL
      guard dest.path.hasPrefix(root.standardizedFileURL.path + "/") else { continue }
      try FileManager.default.createDirectory(
        at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
      do {
        try entry.data.write(to: dest, options: .atomic)
      } catch {
        throw ArchiveError.writeFailed
      }
    }
    completed = true
    return folderName
  }

  static func removeFolder(named name: String) {
    guard !name.isEmpty else { return }
    try? FileManager.default.removeItem(at: folderURL(named: name))
  }

  // MARK: ZIP parsing

  /// Reads an archive without writing it to disk. Kept internal so other
  /// OpenXML-based importers (notably DOCX) can share the same hardened ZIP
  /// implementation instead of shipping a second archive parser.
  static func readEntries(from data: Data) throws -> [Entry] {
    guard data.count <= maximumArchiveBytes else { throw ArchiveError.tooLarge }
    let bytes = [UInt8](data)
    guard bytes.count > 22 else { throw ArchiveError.notZip }

    // Find End Of Central Directory record (signature 0x06054b50), searching back.
    var eocd = -1
    let minStart = max(0, bytes.count - 22 - 65_536)
    var i = bytes.count - 22
    while i >= minStart {
      if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
        eocd = i
        break
      }
      i -= 1
    }
    guard eocd >= 0 else { throw ArchiveError.notZip }

    let entryCount = Int(u16(bytes, eocd + 10))
    guard entryCount > 0, entryCount <= maximumEntryCount else { throw ArchiveError.tooLarge }
    var offset = Int(u32(bytes, eocd + 16))  // start of central directory
    guard offset >= 0, offset < bytes.count else { throw ArchiveError.corrupt }

    var entries: [Entry] = []
    var expandedBytes = 0
    for _ in 0..<entryCount {
      guard offset + 46 <= bytes.count else { throw ArchiveError.corrupt }
      guard bytes[offset] == 0x50, bytes[offset + 1] == 0x4B,
        bytes[offset + 2] == 0x01, bytes[offset + 3] == 0x02
      else { throw ArchiveError.corrupt }

      let flags = u16(bytes, offset + 8)
      let method = u16(bytes, offset + 10)
      let compSize = Int(u32(bytes, offset + 20))
      let uncompSize = Int(u32(bytes, offset + 24))
      let nameLen = Int(u16(bytes, offset + 28))
      let extraLen = Int(u16(bytes, offset + 30))
      let commentLen = Int(u16(bytes, offset + 32))
      let localOffset = Int(u32(bytes, offset + 42))

      let nameStart = offset + 46
      guard nameLen > 0,
        nameStart + nameLen + extraLen + commentLen <= bytes.count,
        compSize <= maximumArchiveBytes, uncompSize <= maximumEntryBytes,
        expandedBytes <= maximumExpandedBytes - uncompSize,
        // Encrypted EPUBs cannot be read by this local ZIP reader.
        flags & 0x0001 == 0
      else { throw ArchiveError.corrupt }
      let name = String(decoding: bytes[nameStart..<nameStart + nameLen], as: UTF8.self)

      guard let payload = inflateEntry(
        bytes, localHeaderOffset: localOffset, method: method,
        compSize: compSize, uncompSize: uncompSize), payload.count == uncompSize
      else { throw ArchiveError.corrupt }
      expandedBytes += payload.count
      entries.append(Entry(path: name, data: payload))

      offset = nameStart + nameLen + extraLen + commentLen
    }
    return entries
  }

  private static func inflateEntry(
    _ bytes: [UInt8], localHeaderOffset: Int, method: UInt16,
    compSize: Int, uncompSize: Int
  ) -> Data? {
    guard localHeaderOffset + 30 <= bytes.count,
      bytes[localHeaderOffset] == 0x50, bytes[localHeaderOffset + 1] == 0x4B
    else { return nil }

    let nameLen = Int(u16(bytes, localHeaderOffset + 26))
    let extraLen = Int(u16(bytes, localHeaderOffset + 28))
    let dataStart = localHeaderOffset + 30 + nameLen + extraLen
    guard compSize >= 0, uncompSize >= 0,
      compSize <= maximumArchiveBytes, uncompSize <= maximumEntryBytes,
      dataStart >= 0, dataStart + compSize <= bytes.count
    else { return nil }

    if method == 0 {  // stored
      guard compSize == uncompSize else { return nil }
      return Data(bytes[dataStart..<dataStart + compSize])
    }
    if method == 8 {  // DEFLATE
      return inflate(Array(bytes[dataStart..<dataStart + compSize]), expectedSize: uncompSize)
    }
    return nil
  }

  /// Raw DEFLATE inflate via Compression (COMPRESSION_ZLIB == raw deflate stream).
  private static func inflate(_ input: [UInt8], expectedSize: Int) -> Data? {
    guard !input.isEmpty else { return Data() }
    guard expectedSize > 0, expectedSize <= maximumEntryBytes else { return nil }
    let capacity = expectedSize
    let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
    defer { dest.deallocate() }

    let written = input.withUnsafeBufferPointer { src -> Int in
      compression_decode_buffer(
        dest, capacity, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
    }
    guard written > 0 else { return nil }
    return Data(bytes: dest, count: written)
  }

  // MARK: Little-endian readers

  private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
    UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
  }

  private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
    UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
  }
}
