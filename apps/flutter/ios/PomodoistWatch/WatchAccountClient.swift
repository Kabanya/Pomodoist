import Foundation
import Security

struct WatchAccountSession: Codable, Equatable {
  var signedIn: Bool
  var supabaseUrl: String?
  var anonKey: String?
  var userId: String?
  var email: String?
  var accessToken: String?
  var refreshToken: String?
  var expiresAt: String?

  var usable: Bool {
    signedIn &&
      supabaseUrl?.isEmpty == false &&
      anonKey?.isEmpty == false &&
      accessToken?.isEmpty == false &&
      refreshToken?.isEmpty == false
  }

  static func decode(from value: Any?) -> WatchAccountSession? {
    guard let dictionary = value as? [String: Any],
      JSONSerialization.isValidJSONObject(dictionary),
      let data = try? JSONSerialization.data(withJSONObject: dictionary)
    else {
      return nil
    }
    return try? JSONDecoder().decode(WatchAccountSession.self, from: data)
  }
}

enum WatchAccountClientError: Error {
  case missingSession
  case invalidResponse
}

final class WatchAccountClient {
  private let session = URLSession(configuration: .ephemeral)
  private let keychainKey = "pomodoist.watch.accountSession.v1"
  private(set) var accountSession: WatchAccountSession?

  init() {
    accountSession = loadSession()
  }

  func updateSession(_ session: WatchAccountSession?) {
    guard let session, session.usable else {
      accountSession = nil
      deleteSession()
      return
    }
    accountSession = session
    saveSession(session)
  }

  func send(command: [String: Any], deviceId: String) async throws -> [String: Any] {
    let session = try await validSession()
    let response = try await post(
      url: "\(session.supabaseUrl!)/functions/v1/pomodoist-watch",
      session: session,
      body: ["deviceId": deviceId, "command": command]
    )
    return response
  }

  private func validSession() async throws -> WatchAccountSession {
    guard var current = accountSession, current.usable else {
      throw WatchAccountClientError.missingSession
    }
    if let expiresAt = current.expiresAt.flatMap(WatchDateCoding.date),
      expiresAt.timeIntervalSinceNow > 60
    {
      return current
    }
    current = try await refresh(current)
    accountSession = current
    saveSession(current)
    return current
  }

  private func refresh(_ current: WatchAccountSession) async throws -> WatchAccountSession {
    guard let supabaseUrl = current.supabaseUrl,
      let anonKey = current.anonKey,
      let refreshToken = current.refreshToken
    else {
      throw WatchAccountClientError.missingSession
    }
    var request = URLRequest(url: URL(string: "\(supabaseUrl)/auth/v1/token?grant_type=refresh_token")!)
    request.httpMethod = "POST"
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["refresh_token": refreshToken])
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let accessToken = json["access_token"] as? String
    else {
      throw WatchAccountClientError.invalidResponse
    }
    let expiresIn = json["expires_in"] as? Double ?? 3600
    return WatchAccountSession(
      signedIn: true,
      supabaseUrl: supabaseUrl,
      anonKey: anonKey,
      userId: current.userId,
      email: current.email,
      accessToken: accessToken,
      refreshToken: (json["refresh_token"] as? String) ?? refreshToken,
      expiresAt: WatchDateCoding.string(from: Date().addingTimeInterval(expiresIn))
    )
  }

  private func post(
    url: String,
    session account: WatchAccountSession,
    body: [String: Any]
  ) async throws -> [String: Any] {
    guard let endpoint = URL(string: url),
      let anonKey = account.anonKey,
      let accessToken = account.accessToken
    else {
      throw WatchAccountClientError.missingSession
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 8
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    let (data, response) = try await self.session.data(for: request)
    guard let http = response as? HTTPURLResponse,
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw WatchAccountClientError.invalidResponse
    }
    if !(200..<300 ~= http.statusCode), json["error"] == nil {
      throw WatchAccountClientError.invalidResponse
    }
    return json
  }

  private func loadSession() -> WatchAccountSession? {
    var query = keychainQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else {
      return nil
    }
    return try? JSONDecoder().decode(WatchAccountSession.self, from: data)
  }

  private func saveSession(_ session: WatchAccountSession) {
    guard let data = try? JSONEncoder().encode(session) else {
      return
    }
    deleteSession()
    var query = keychainQuery
    query[kSecValueData as String] = data
    SecItemAdd(query as CFDictionary, nil)
  }

  private func deleteSession() {
    SecItemDelete(keychainQuery as CFDictionary)
  }

  private var keychainQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainKey,
      kSecAttrAccount as String: keychainKey,
    ]
  }
}
