import CryptoKit
import Foundation

enum OAuth1 {
    struct Credentials: Sendable, Hashable {
        let consumerKey: String
        let consumerSecret: String
    }

    struct Token: Sendable, Hashable, Codable {
        let token: String
        let tokenSecret: String

        static let none = Token(token: "", tokenSecret: "")
    }

    static func signedRequest(
        method: String,
        url: URL,
        credentials: Credentials,
        token: Token,
        extraOAuthParameters: [String: String] = [:],
        bodyParameters: [String: String] = [:],
        additionalHeaders: [String: String] = [:]
    ) -> URLRequest {
        var oauthParameters: [String: String] = [
            "oauth_consumer_key": credentials.consumerKey,
            "oauth_nonce": UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            "oauth_signature_method": "HMAC-SHA1",
            "oauth_timestamp": String(Int(Date().timeIntervalSince1970)),
            "oauth_version": "1.0",
        ]
        if !token.token.isEmpty {
            oauthParameters["oauth_token"] = token.token
        }
        for (key, value) in extraOAuthParameters {
            oauthParameters[key] = value
        }

        var allParameters: [(String, String)] = oauthParameters.map { ($0.key, $0.value) }
        if let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for item in queryItems {
                allParameters.append((item.name, item.value ?? ""))
            }
        }
        for (key, value) in bodyParameters {
            allParameters.append((key, value))
        }

        let encoded: [(String, String)] = allParameters.map { pair in
            (pair.0.oauthEncoded, pair.1.oauthEncoded)
        }
        let sorted: [(String, String)] = encoded.sorted { lhs, rhs in
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }
        let normalized: String = sorted
            .map { "\($0.0)=\($0.1)" }
            .joined(separator: "&")

        var baseComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        baseComponents?.query = nil
        baseComponents?.fragment = nil
        let baseURLString = baseComponents?.string ?? url.absoluteString

        let baseString = "\(method)&\(baseURLString.oauthEncoded)&\(normalized.oauthEncoded)"
        let signingKey = "\(credentials.consumerSecret.oauthEncoded)&\(token.tokenSecret.oauthEncoded)"

        let mac = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(baseString.utf8),
            using: SymmetricKey(data: Data(signingKey.utf8))
        )
        oauthParameters["oauth_signature"] = Data(mac).base64EncodedString()

        let authHeader = "OAuth " + oauthParameters
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\"\($0.value.oauthEncoded)\"" }
            .joined(separator: ", ")

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if !bodyParameters.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = bodyParameters
                .map { "\($0.key.oauthEncoded)=\($0.value.oauthEncoded)" }
                .joined(separator: "&")
            request.httpBody = Data(body.utf8)
        }
        return request
    }
}

private extension String {
    var oauthEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .oauthAllowed) ?? self
    }
}

private extension CharacterSet {
    static let oauthAllowed: CharacterSet = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )
}
