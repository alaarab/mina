import Foundation
import Security

/// Nanit has no public API. This talks to the same endpoints the Nanit app
/// uses, as documented by the Home Assistant community bridge. It can break
/// whenever Nanit changes their backend, so every call fails soft.
struct NanitTokens: Codable {
    var accessToken: String
    var refreshToken: String
    var issuedAt: Date
}

struct NanitBaby: Codable, Identifiable, Equatable {
    let uid: String
    let name: String
    let cameraUID: String?
    var id: String { uid }

    enum CodingKeys: String, CodingKey { case uid, name, cameraUID = "camera_uid" }
}

struct NanitMessage: Identifiable, Equatable {
    let id: Int
    let type: String
    let time: Date

    init(id: Int, type: String, time: Date) {
        self.id = id
        self.type = type
        self.time = time
    }
}

extension NanitMessage: Decodable {
    enum CodingKeys: String, CodingKey { case id, type, time }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        type = (try? container.decode(String.self, forKey: .type)) ?? ""
        if let seconds = try? container.decode(Double.self, forKey: .time) {
            time = Date(timeIntervalSince1970: seconds)
        } else if let text = try? container.decode(String.self, forKey: .time), let date = ISO8601DateFormatter().date(from: text) {
            time = date
        } else {
            time = .distantPast
        }
    }
}

enum NanitError: LocalizedError {
    case badCredentials
    case badCode
    case sessionExpired
    case unexpected(Int, String)

    var errorDescription: String? {
        switch self {
        case .badCredentials: return "Nanit didn't accept that email and password."
        case .badCode: return "That code wasn't accepted. Check the newest email from Nanit."
        case .sessionExpired: return "Nanit signed this phone out. Connect again in Settings."
        case .unexpected(let status, let body): return "Nanit replied with \(status): \(body.prefix(120))"
        }
    }
}

final class NanitClient {
    static let base = URL(string: "https://api.nanit.com")!

    enum LoginResult: Equatable {
        case needsCode(mfaToken: String)
        case tokens(NanitTokens)

        static func == (lhs: LoginResult, rhs: LoginResult) -> Bool {
            switch (lhs, rhs) {
            case (.needsCode(let a), .needsCode(let b)): return a == b
            case (.tokens(let a), .tokens(let b)): return a.refreshToken == b.refreshToken
            default: return false
            }
        }
    }

    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    /// First call without a code: Nanit emails one and returns an mfa_token.
    /// Second call with both finishes the login.
    func login(email: String, password: String, mfaToken: String? = nil, code: String? = nil) async throws -> LoginResult {
        var body: [String: String] = ["email": email, "password": password, "channel": "email"]
        if let mfaToken, let code {
            body["mfa_token"] = mfaToken
            body["mfa_code"] = code
        }
        let (status, json) = try await post("login", body: body, token: nil)
        if status == 401 { throw mfaToken == nil ? NanitError.badCredentials : NanitError.badCode }
        if let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String {
            return .tokens(NanitTokens(accessToken: access, refreshToken: refresh, issuedAt: .now))
        }
        if let mfa = json["mfa_token"] as? String { return .needsCode(mfaToken: mfa) }
        throw NanitError.unexpected(status, String(describing: json))
    }

    func refresh(_ refreshToken: String) async throws -> NanitTokens {
        let (status, json) = try await post("tokens/refresh", body: ["refresh_token": refreshToken], token: nil)
        if status == 404 || status == 401 { throw NanitError.sessionExpired }
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw NanitError.unexpected(status, String(describing: json))
        }
        return NanitTokens(accessToken: access, refreshToken: refresh, issuedAt: .now)
    }

    func babies(token: String) async throws -> [NanitBaby] {
        struct Payload: Decodable { let babies: [NanitBaby] }
        return try await get("babies", token: token, as: Payload.self).babies
    }

    func messages(babyUID: String, limit: Int = 100, token: String) async throws -> [NanitMessage] {
        struct Payload: Decodable { let messages: [NanitMessage] }
        return try await get("babies/\(babyUID)/messages?limit=\(limit)", token: token, as: Payload.self).messages
    }

    // MARK: Transport

    private func request(_ path: String, method: String, token: String?) -> URLRequest {
        var request = URLRequest(url: Self.base.appendingPathComponent(path.split(separator: "?").first.map(String.init) ?? path))
        if let query = path.split(separator: "?").dropFirst().first {
            request.url = URL(string: Self.base.absoluteString + "/" + path)
            _ = query
        }
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "nanit-api-version")
        if let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func post(_ path: String, body: [String: String], token: String?) async throws -> (Int, [String: Any]) {
        var request = request(path, method: "POST", token: token)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (status, json)
    }

    private func get<T: Decodable>(_ path: String, token: String, as type: T.Type) async throws -> T {
        let request = request(path, method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw NanitError.sessionExpired }
        guard (200..<300).contains(status) else { throw NanitError.unexpected(status, String(data: data, encoding: .utf8) ?? "") }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

/// Tokens live in the Keychain, readable after first unlock so background
/// refresh can use them.
enum Keychain {
    private static let service = "com.alaarab.mina.nanit"

    static func set(_ data: Data, for account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ account: String) -> Data? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
