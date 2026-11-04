import Foundation

/// Intercepts URLSession traffic in tests so the Discogs, MusicBrainz and
/// Cover Art Archive clients can be driven with canned JSON, no network or
/// real credentials needed.
final class StubURLProtocol: URLProtocol {
    /// A responder that throws fails the request with that error, e.g.
    /// `URLError(.notConnectedToInternet)` to act offline.
    nonisolated(unsafe) static var responder: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        do {
            let (response, data) = try responder(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

enum StubSession {
    static func make() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

func stubHTTPResponse(for request: URLRequest, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: ["X-Discogs-Ratelimit-Remaining": "50"]
    )!
}

func requestedPage(_ request: URLRequest) -> Int {
    guard let url = request.url,
          let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
              .queryItems?.first(where: { $0.name == "page" })?.value,
          let page = Int(value)
    else { return 1 }
    return page
}

/// Builds a Discogs collection-page JSON payload.
func collectionPageJSON(page: Int, pages: Int, items: Int, releases: [[String: Any]]) -> Data {
    let object: [String: Any] = [
        "pagination": ["page": page, "pages": pages, "per_page": 100, "items": items],
        "releases": releases,
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

/// Builds a MusicBrainz release-search payload. Each release is in a release
/// group whose MBID is the release's plus "-group"; a nil score is left out.
func musicBrainzSearchJSON(releases: [(id: String, score: Int?)]) -> Data {
    let object: [String: Any] = [
        "created": "2026-11-04T00:00:00.000Z",
        "count": releases.count,
        "offset": 0,
        "releases": releases.map { release -> [String: Any] in
            var json: [String: Any] = ["id": release.id, "release-group": ["id": "\(release.id)-group"]]
            if let score = release.score {
                json["score"] = score
            }
            return json
        },
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

/// Builds a Cover Art Archive listing with one front image.
func coverArtListingJSON(image: String) -> Data {
    let object: [String: Any] = [
        "images": [["front": true, "image": image, "thumbnails": [String: String]()]],
    ]
    return try! JSONSerialization.data(withJSONObject: object)
}

/// Builds a single collection release entry.
func releaseJSON(
    id: Int,
    dateAdded: String,
    format: String = "Vinyl",
    title: String = "Title",
    coverImage: String = "https://example.com/cover.jpg"
) -> [String: Any] {
    [
        "id": id,
        "instance_id": id * 10,
        "date_added": dateAdded,
        "basic_information": [
            "id": id,
            "title": title,
            "year": 2020,
            "thumb": "https://example.com/thumb.jpg",
            "cover_image": coverImage,
            "artists": [["name": "Artist"]],
            "labels": [["name": "Label", "catno": "CAT-1"]],
            "formats": [["name": format, "descriptions": ["LP"]]],
            "genres": ["Rock"],
            "styles": ["Indie Rock"],
        ],
    ]
}
