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

    init(uid: String, name: String, cameraUID: String?) {
        self.uid = uid
        self.name = name
        self.cameraUID = cameraUID
    }

    /// Only the uid is required; a baby with no name is still a camera you can pick.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        uid = try container.decode(String.self, forKey: .uid)
        name = (try? container.decode(String.self, forKey: .name)) ?? "Baby"
        cameraUID = try? container.decode(String.self, forKey: .cameraUID)
    }
}

/// Decodes a JSON array element by element and drops the ones that don't fit.
/// Nanit's API is unofficial: one unexpected record must not lose the reply.
struct LossyArray<Element: Decodable>: Decodable {
    let values: [Element]

    private struct Skip: Decodable {}

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var values: [Element] = []
        while !container.isAtEnd {
            do {
                values.append(try container.decode(Element.self))
            } catch {
                // A failed decode leaves the cursor where it was; step over it.
                _ = try? container.decode(Skip.self)
            }
        }
        self.values = values
    }
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
        if let number = try? container.decode(Int.self, forKey: .id) {
            id = number
        } else if let text = try? container.decode(String.self, forKey: .id), let number = Int(text) {
            id = number
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: container, debugDescription: "no usable id")
        }
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

/// Strips anything that could be a credential out of text that is about to be
/// shown in the UI. Nanit's error bodies are undocumented, so this errs towards
/// deleting too much: any value of a key that looks secret, and any bare run of
/// 20+ token characters.
enum NanitRedaction {
    private static let secretKeys = ["token", "password", "secret", "code", "auth", "key", "session", "cookie"]

    static func scrub(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        var run = ""          // the word being read
        var lastWord = ""     // the word before it
        var currentKey = ""   // the word before the nearest ":" or "="

        func flush() {
            guard !run.isEmpty else { return }
            let keyIsSecret = secretKeys.contains { currentKey.lowercased().contains($0) }
            output += (keyIsSecret || looksLikeToken(run)) ? "***" : run
            lastWord = run
            run = ""
        }

        for character in text {
            if character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." {
                run.append(character)
                continue
            }
            flush()
            switch character {
            case ":", "=": currentKey = lastWord          // `"access_token": <secret>`
            case ",", ";", "{", "}", "[", "]", "\n": currentKey = ""
            default: break
            }
            output.append(character)
        }
        flush()
        return output
    }

    /// A long unbroken run of token-ish characters, or anything shaped like a JWT.
    static func looksLikeToken(_ value: String) -> Bool {
        if value.split(separator: ".").count == 3 && value.count >= 20 { return true }
        guard value.count >= 20 else { return false }
        return value.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
            && value.contains(where: { $0.isNumber })
    }

    /// The shape of a reply, with none of its values: "status, keys: babies, next".
    static func keys(of json: [String: Any]) -> String {
        json.keys.sorted().joined(separator: ", ")
    }
}

enum NanitError: LocalizedError {
    case badCredentials
    case badCode
    case sessionExpired
    case unexpected(Int, String)

    /// `body` is always run through `NanitRedaction.scrub` at the call site, so
    /// no access token, refresh token or password reaches the UI or a log.
    var errorDescription: String? {
        switch self {
        case .badCredentials: return "Nanit didn't accept that email and password."
        case .badCode: return "That code wasn't accepted. Check the newest email from Nanit."
        case .sessionExpired: return "Nanit signed this phone out. Connect again in Settings."
        case .unexpected(let status, let body):
            let detail = NanitRedaction.scrub(body).prefix(120)
            return detail.isEmpty ? "Nanit replied with \(status)." : "Nanit replied with \(status): \(detail)"
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

    /// Ephemeral: no cookie jar, no credential store and no URL cache on disk,
    /// so nothing about the Nanit session is written outside the Keychain.
    /// Requests never fall back below TLS 1.2 and never wait more than 20s.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    private let session: URLSession

    init(session: URLSession? = nil) { self.session = session ?? Self.makeSession() }

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
        throw NanitError.unexpected(status, "unrecognised reply (\(NanitRedaction.keys(of: json)))")
    }

    func refresh(_ refreshToken: String) async throws -> NanitTokens {
        let (status, json) = try await post("tokens/refresh", body: ["refresh_token": refreshToken], token: nil)
        if status == 404 || status == 401 { throw NanitError.sessionExpired }
        guard let access = json["access_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw NanitError.unexpected(status, "unrecognised reply (\(NanitRedaction.keys(of: json)))")
        }
        return NanitTokens(accessToken: access, refreshToken: refresh, issuedAt: .now)
    }

    func babies(token: String) async throws -> [NanitBaby] {
        struct Payload: Decodable {
            let babies: LossyArray<NanitBaby>?
        }
        return try await get("babies", token: token, as: Payload.self).babies?.values ?? []
    }

    func messages(babyUID: String, limit: Int = 100, token: String) async throws -> [NanitMessage] {
        struct Payload: Decodable {
            let messages: LossyArray<NanitMessage>?
        }
        let clamped = min(max(limit, 1), 500)
        return try await get("babies/\(babyUID)/messages", query: ["limit": String(clamped)],
                             token: token, as: Payload.self).messages?.values ?? []
    }

    // MARK: Transport

    private func request(_ path: String, query: [String: String] = [:], method: String, token: String?) -> URLRequest {
        var url = Self.base
        for segment in path.split(separator: "/") { url.appendPathComponent(String(segment)) }
        if !query.isEmpty, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components.url ?? url
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "nanit-api-version")
        // Nanit wants the raw token, not a Bearer prefix.
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

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:], token: String, as type: T.Type) async throws -> T {
        let request = request(path, query: query, method: "GET", token: token)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw NanitError.sessionExpired }
        guard (200..<300).contains(status) else {
            throw NanitError.unexpected(status, String(data: data.prefix(512), encoding: .utf8) ?? "")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            // Unofficial API: a shape we don't know is a soft failure, not a crash,
            // and the decoding error itself can quote payload values.
            throw NanitError.unexpected(status, "reply didn't look like \(T.self)")
        }
    }
}

/// Tokens live in the Keychain, readable after first unlock so background
/// refresh can use them while the phone is locked, and never synchronised to
/// iCloud Keychain: the token is this phone's session with Nanit, and a copy of
/// it on the partner's phone would be a second silent sign-in.
enum Keychain {
    private static let service = "com.alaarab.mina.nanit"

    /// The lookup half of every query. `kSecAttrSynchronizable: false` is part
    /// of an item's identity, so it has to be on reads and deletes too or they
    /// would miss the item.
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        SecItemDelete(query(account) as CFDictionary)
        var add = query(account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ account: String) -> Data? {
        var lookup = query(account)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
        // Items written before this app set kSecAttrSynchronizable explicitly
        // carry no such attribute, so sweep both kinds on disconnect.
        var any = query(account)
        any[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(any as CFDictionary)
    }
}
