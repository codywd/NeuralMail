import Foundation

struct NMAIProfile: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var baseURL: String
    var model: String
    var apiKeyKeychainKey: String

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        model: String = "",
        apiKeyKeychainKey: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.apiKeyKeychainKey = apiKeyKeychainKey
    }
}
