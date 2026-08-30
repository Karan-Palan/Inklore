import Foundation

public struct TenxStorageObject: Codable, Sendable, Identifiable {
    public let id: String
    public let bucket: String?
    public let filename: String?
    public let contentType: String?
    public let sizeBytes: Int?
    public let checksum: String?
    public let status: String?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        id = try container.decodeString("id")
        bucket = try container.decodeOptionalString("bucket", "logicalBucket")
        filename = try container.decodeOptionalString("filename")
        contentType = try container.decodeOptionalString("content_type", "contentType")
        sizeBytes = try container.decodeOptionalInt("size_bytes", "sizeBytes")
        checksum = try container.decodeOptionalString("checksum")
        status = try container.decodeOptionalString("status")
    }
}

public struct TenxStorageUpload: Codable, Sendable {
    public let method: String
    public let url: URL
    public let expiresInSeconds: Int
    public let headers: [String: String]?

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        method = try container.decodeString("method")
        url = try container.decodeValue(URL.self, "url")
        expiresInSeconds = try container.decodeInt("expires_in_seconds", "expiresInSeconds", defaultValue: 0)
        headers = try container.decodeOptionalValue([String: String].self, "headers")
    }
}

public struct TenxStorageUploadResponse: Codable, Sendable {
    public let object: TenxStorageObject
    public let upload: TenxStorageUpload
}

public struct TenxStorageDownload: Codable, Sendable {
    public let method: String
    public let url: URL
    public let expiresInSeconds: Int

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TenxFlexibleCodingKey.self)
        method = try container.decodeString("method")
        url = try container.decodeValue(URL.self, "url")
        expiresInSeconds = try container.decodeInt("expires_in_seconds", "expiresInSeconds", defaultValue: 0)
    }
}

public struct TenxStorageDownloadResponse: Codable, Sendable {
    public let object: TenxStorageObject
    public let download: TenxStorageDownload
}

public struct TenxStorageListResponse: Codable, Sendable {
    public let objects: [TenxStorageObject]
}

public struct TenxStorage {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func createUpload(
        bucket: String,
        filename: String,
        contentType: String? = nil,
        sizeBytes: Int? = nil,
        checksum: String? = nil,
        accessToken: String
    ) async throws -> TenxStorageUploadResponse {
        var body: [String: Any] = ["bucket": bucket, "filename": filename]
        body["contentType"] = contentType
        body["sizeBytes"] = sizeBytes
        body["checksum"] = checksum
        return try await post("uploads", body: body, accessToken: accessToken)
    }

    public func upload(data: Data, using upload: TenxStorageUpload) async throws {
        var request = URLRequest(url: upload.url)
        request.httpMethod = upload.method
        upload.headers?.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = data
        _ = try await session.tenxData(for: request)
    }

    /// Sign and upload bytes in one call, transparently re-signing once if the
    /// R2 signer URL expires before the transfer completes (design doc §24).
    @discardableResult
    public func upload(
        data: Data,
        bucket: String,
        filename: String,
        contentType: String? = nil,
        sizeBytes: Int? = nil,
        checksum: String? = nil,
        accessToken: String
    ) async throws -> TenxStorageObject {
        func sign() async throws -> TenxStorageUploadResponse {
            try await createUpload(
                bucket: bucket,
                filename: filename,
                contentType: contentType,
                sizeBytes: sizeBytes ?? data.count,
                checksum: checksum,
                accessToken: accessToken
            )
        }
        var response = try await sign()
        do {
            try await upload(data: data, using: response.upload)
        } catch let error where Self.isExpiredSignedURL(error) {
            response = try await sign()
            try await upload(data: data, using: response.upload)
        }
        // Confirm so the object flips from `pending` to `active`. Without this
        // the bytes are stored but every later download returns 409 "Storage
        // object is not active", so the one-shot upload must confirm before
        // handing back a usable object.
        return try await confirmUpload(
            objectID: response.object.id,
            sizeBytes: sizeBytes ?? data.count,
            checksum: checksum,
            accessToken: accessToken
        )
    }

    public func confirmUpload(objectID: String, sizeBytes: Int? = nil, checksum: String? = nil, accessToken: String) async throws -> TenxStorageObject {
        var body: [String: Any] = [:]
        body["sizeBytes"] = sizeBytes
        body["checksum"] = checksum
        struct Response: Codable { let object: TenxStorageObject }
        return try await post("uploads/\(objectID)/confirm", body: body, accessToken: accessToken, as: Response.self).object
    }

    public func downloadURL(objectID: String, accessToken: String) async throws -> TenxStorageDownloadResponse {
        try await post("download-url", body: ["objectId": objectID], accessToken: accessToken)
    }

    /// Sign and download an object's bytes, transparently re-signing once if the
    /// R2 signer URL expires before the transfer completes (design doc §24).
    public func download(objectID: String, accessToken: String) async throws -> Data {
        var response = try await downloadURL(objectID: objectID, accessToken: accessToken)
        do {
            return try await fetch(using: response.download)
        } catch let error where Self.isExpiredSignedURL(error) {
            response = try await downloadURL(objectID: objectID, accessToken: accessToken)
            return try await fetch(using: response.download)
        }
    }

    private func fetch(using download: TenxStorageDownload) async throws -> Data {
        var request = URLRequest(url: download.url)
        request.httpMethod = download.method
        return try await session.tenxData(for: request)
    }

    /// A 403/400 from object storage on a *signed URL* transfer means the
    /// presigned URL expired or its signature is no longer valid; both are
    /// recoverable by re-signing once.
    private static func isExpiredSignedURL(_ error: Error) -> Bool {
        if case let TenxBackendError.requestFailed(status, _) = error {
            return status == 403 || status == 400
        }
        return false
    }

    public func listObjects(bucket: String? = nil, limit: Int = 100, accessToken: String) async throws -> [TenxStorageObject] {
        guard var components = URLComponents(url: TenxProject.storageBaseURL.appendingPathComponent("objects"), resolvingAgainstBaseURL: false) else {
            throw TenxBackendError.invalidResponse
        }
        var queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let bucket, !bucket.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "bucket", value: bucket))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw TenxBackendError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await session.tenxDecoded(TenxStorageListResponse.self, for: request).objects
    }

    public func deleteObject(objectID: String, accessToken: String) async throws -> TenxStorageObject {
        var request = URLRequest(url: TenxProject.storageBaseURL.appendingPathComponent("objects/\(objectID)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        struct Response: Codable { let object: TenxStorageObject }
        return try await session.tenxDecoded(Response.self, for: request).object
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], accessToken: String, as type: T.Type = T.self) async throws -> T {
        var request = URLRequest(url: TenxProject.storageBaseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await session.tenxDecoded(T.self, for: request)
    }
}