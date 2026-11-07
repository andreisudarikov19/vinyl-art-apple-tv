import Foundation
import Testing
@testable import VinylForAppleTV

struct OAuth1Tests {
    private let credentials = OAuth1.Credentials(consumerKey: "key", consumerSecret: "secret")
    private let url = URL(string: "https://api.discogs.com/oauth/access_token")!

    // OAuth Core 1.0, Appendix A.5: https://oauth.net/core/1.0/#sig_base_example
    private func oauthCoreExampleRequest() -> URLRequest {
        OAuth1.signedRequest(
            method: "GET",
            url: URL(string: "http://photos.example.net/photos?file=vacation.jpg&size=original")!,
            credentials: OAuth1.Credentials(consumerKey: "dpf43f3p2l4k3l03", consumerSecret: "kd94hf93k423kf44"),
            token: OAuth1.Token(token: "nnch734d00sl2jdk", tokenSecret: "pfkkdhi9sl3r4s00"),
            nonce: "kllo9940pd9333jh",
            timestamp: Date(timeIntervalSince1970: 1191242096)
        )
    }

    /// What a body parameter's value encodes to.
    private func encoded(_ value: String) throws -> String {
        let request = OAuth1.signedRequest(
            method: "POST", url: url, credentials: credentials, token: .none, bodyParameters: ["v": value]
        )
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        return String(body.dropFirst("v=".count))
    }

    @Test func baseStringMatchesTheRFC5849Example() {
        // RFC 5849 §3.4.1.1; its errata change the example's signature, not the base string.
        let baseString = OAuth1.signatureBaseString(
            method: "POST",
            url: URL(string: "http://example.com/request?b5=%3D%253D&a3=a&c%40=&a2=r%20b")!,
            oauthParameters: [
                "oauth_consumer_key": "9djdj82h48djs9d2",
                "oauth_token": "kkk9d7dh3k39sjv7",
                "oauth_signature_method": "HMAC-SHA1",
                "oauth_timestamp": "137131201",
                "oauth_nonce": "7d8f3e4a",
            ],
            bodyParameters: ["c2": "", "a3": "2 q"]
        )

        #expect(baseString == """
            POST&http%3A%2F%2Fexample.com%2Frequest&a2%3Dr%2520b%26a3%3D2%2520q\
            %26a3%3Da%26b5%3D%253D%25253D%26c%2540%3D%26c2%3D%26oauth_consumer_\
            key%3D9djdj82h48djs9d2%26oauth_nonce%3D7d8f3e4a%26oauth_signature_m\
            ethod%3DHMAC-SHA1%26oauth_timestamp%3D137131201%26oauth_token%3Dkkk\
            9d7dh3k39sjv7
            """)
    }

    @Test func signatureMatchesTheOAuthCoreExample() {
        #expect(authorizationParameters(oauthCoreExampleRequest())["oauth_signature"] == "tR3+Ty81lMeYAr/Fid0kMTYa/WM=")
    }

    @Test func authorizationHeaderListsSortedQuotedEncodedParameters() {
        #expect(oauthCoreExampleRequest().value(forHTTPHeaderField: "Authorization") == """
            OAuth oauth_consumer_key="dpf43f3p2l4k3l03", oauth_nonce="kllo9940pd9333jh", \
            oauth_signature="tR3%2BTy81lMeYAr%2FFid0kMTYa%2FWM%3D", oauth_signature_method="HMAC-SHA1", \
            oauth_timestamp="1191242096", oauth_token="nnch734d00sl2jdk", oauth_version="1.0"
            """)
    }

    @Test func encodingFollowsRFC3986() throws {
        #expect(try encoded("AZaz09-._~") == "AZaz09-._~")
        #expect(try encoded("a b") == "a%20b")
        #expect(try encoded("+*&=/") == "%2B%2A%26%3D%2F")
        #expect(try encoded("é") == "%C3%A9")
    }

    @Test func requestWithoutATokenLeavesOutOAuthToken() {
        let request = OAuth1.signedRequest(method: "GET", url: url, credentials: credentials, token: .none)

        let parameters = authorizationParameters(request)
        #expect(parameters["oauth_token"] == nil)
        #expect(parameters["oauth_signature"] != nil)
    }

    @Test func extraOAuthParametersAppearInTheHeader() {
        let request = OAuth1.signedRequest(
            method: "POST",
            url: url,
            credentials: credentials,
            token: OAuth1.Token(token: "request", tokenSecret: "secret"),
            extraOAuthParameters: ["oauth_callback": "oob", "oauth_verifier": "CODE"]
        )

        let parameters = authorizationParameters(request)
        #expect(parameters["oauth_callback"] == "oob")
        #expect(parameters["oauth_verifier"] == "CODE")
        #expect(parameters["oauth_token"] == "request")
    }

    @Test func bodyParametersAreFormEncoded() throws {
        let request = OAuth1.signedRequest(
            method: "POST", url: url, credentials: credentials, token: .none,
            bodyParameters: ["a": "1", "b": "x y"]
        )

        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        #expect(Set(body.split(separator: "&")) == ["a=1", "b=x%20y"])
    }

    @Test func requestWithoutBodyParametersHasNoBody() {
        let request = OAuth1.signedRequest(method: "GET", url: url, credentials: credentials, token: .none)

        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }
}
