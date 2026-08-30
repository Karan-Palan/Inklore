import Foundation
import SwiftUI

/// Shared TenX preview hooks injected into generated projects.
enum TenXPreviewSupport {
    /// The file used by preview capture to discover the currently visible screen.
    private static let viewLogURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("tenx-view-log.json")
    }()

    /// The file used by preview diagnostics to expose readable runtime breadcrumbs.
    private static let runtimeLogURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("tenx-runtime.log")
    }()

    /// Self-contained ISO-8601 formatter (the generated project has no TenX utilities).
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Records the visible screen for TenX preview capture.
    static func track(_ viewName: String) {
        let entry: [String: Any] = [
            "view": viewName,
            "timestamp": Date().timeIntervalSince1970
        ]

        if let data = try? JSONSerialization.data(withJSONObject: entry) {
            try? data.write(to: viewLogURL, options: .atomic)
        }
        log("view=\(viewName)")
    }

    /// Records readable runtime diagnostics for live_preview_logs.
    static func log(_ message: String) {
        let normalizedMessage = message
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let timestamp = iso8601Formatter.string(from: Date())
        let line = "\(timestamp) \(normalizedMessage)"
        print("[10x-runtime] \(line)")

        guard let data = "\(line)\n".data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: runtimeLogURL.path),
           let handle = try? FileHandle(forWritingTo: runtimeLogURL) {
            _ = handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: runtimeLogURL, options: .atomic)
        }
    }
}

/// Backward-compatible tracking shim for older generated screen code.
enum TenXViewTracker {
    static func track(_ viewName: String) {
        TenXPreviewSupport.track(viewName)
    }
}

struct TenXPreviewTrackerModifier: ViewModifier {
    let viewName: String

    func body(content: Content) -> some View {
        content
            .task(id: viewName) {
                TenXPreviewSupport.track(viewName)
            }
            .onAppear {
                TenXPreviewSupport.track(viewName)
            }
    }
}

extension View {
    /// Preview-tracking hook injected by 10x. Namespaced so generated code never
    /// redeclares it (a plain `trackView` collided with model-authored helpers).
    func __tenxTrackView(_ name: String) -> some View {
        modifier(TenXPreviewTrackerModifier(viewName: name))
    }
}