import Foundation

public struct BackendClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func request(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = [],
        body: Data? = nil,
        accessToken: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: try url(path: path, queryItems: queryItems))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken, !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = body
        return try await session.tenxData(for: request)
    }

    public func get<Response: Decodable>(
        _ type: Response.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Response {
        let data = try await request(
            path: path,
            method: "GET",
            queryItems: queryItems,
            accessToken: accessToken,
            headers: headers
        )
        return try JSONDecoder().decode(Response.self, from: data)
    }

    public func send<RequestBody: Encodable, Response: Decodable>(
        _ type: Response.Type,
        path: String,
        method: String = "POST",
        body: RequestBody,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) async throws -> Response {
        let data = try encoder.encode(body)
        let responseData = try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: data,
            accessToken: accessToken,
            headers: headers
        )
        return try JSONDecoder().decode(Response.self, from: responseData)
    }

    public func send<RequestBody: Encodable>(
        path: String,
        method: String = "POST",
        body: RequestBody,
        queryItems: [URLQueryItem] = [],
        accessToken: String? = nil,
        headers: [String: String] = [:],
        encoder: JSONEncoder = JSONEncoder()
    ) async throws -> Data {
        let data = try encoder.encode(body)
        return try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: data,
            accessToken: accessToken,
            headers: headers
        )
    }

    private func url(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: TenxProject.projectAPIURL, resolvingAgainstBaseURL: false) else {
            throw TenxBackendError.invalidResponse
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let joined = [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.path = "/" + joined
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw TenxBackendError.invalidResponse
        }
        return url
    }
}