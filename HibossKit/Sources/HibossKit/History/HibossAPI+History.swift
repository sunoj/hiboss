// Fetches full or incremental history using an opaque server cursor.
// Exports HibossAPI history paging.
// Depends on Foundation URLSession and the shared history contracts.

import Foundation

extension HibossAPI {
    public func fetchHistoryPage(updatedAfter: String?) async throws -> HistoryResponse {
        var items = [
            URLQueryItem(name: "direction", value: "all"),
            URLQueryItem(name: "limit", value: String(AppConstants.API.historyLimit)),
        ]
        if let updatedAfter { items.append(URLQueryItem(name: "updated_after", value: updatedAfter)) }
        let endpoint = apiURL.appendingPathComponent("messages").appending(queryItems: items)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw HibossAPIError.invalidResponse
        }
        components.percentEncodedQuery = components.percentEncodedQuery?
            .replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw HibossAPIError.invalidResponse }
        let (data, response) = try await session.data(for: authorizedRequest(url: url, method: "GET"))
        try validate(response)
        return try JSONDecoder().decode(HistoryResponse.self, from: data)
    }

}
