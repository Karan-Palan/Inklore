import Foundation

public struct TenxData {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func select(table: String, queryItems: [URLQueryItem] = [], accessToken: String) async throws -> Data {
        try await request(table: table, method: "GET", queryItems: queryItems, body: Optional<Data>.none, accessToken: accessToken)
    }

    public func insert<T: Encodable>(table: String, value: T, accessToken: String) async throws -> Data {
        let body = try JSONEncoder().encode(value)
        return try await request(table: table, method: "POST", body: body, accessToken: accessToken)
    }

    public func update<T: Encodable>(table: String, queryItems: [URLQueryItem], value: T, accessToken: String) async throws -> Data {
        let body = try JSONEncoder().encode(value)
        return try await request(table: table, method: "PATCH", queryItems: queryItems, body: body, accessToken: accessToken)
    }

    public func delete(table: String, queryItems: [URLQueryItem], accessToken: String) async throws -> Data {
        try await request(table: table, method: "DELETE", queryItems: queryItems, body: Optional<Data>.none, accessToken: accessToken)
    }

    private func request(
        table: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        body: Data?,
        accessToken: String
    ) async throws -> Data {
        guard let baseURL = TenxProject.dataAPIURL else {
            throw TenxBackendError.missingDataAPIURL
        }
        guard var components = URLComponents(url: baseURL.appendingPathComponent(table), resolvingAgainstBaseURL: false) else {
            throw TenxBackendError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw TenxBackendError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method == "POST" || method == "PATCH" {
            request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        }
        request.httpBody = body
        return try await session.tenxData(for: request, retryingTransientJWKMiss: true)
    }
}