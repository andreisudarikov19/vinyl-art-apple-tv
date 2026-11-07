import Foundation
import Testing
@testable import VinylForAppleTV

@Suite(.serialized)
struct CoverArtArchiveTests {
    private func frontCover(listing: Data) async throws -> String? {
        StubURLProtocol.responder = { request in (stubHTTPResponse(for: request), listing) }
        return try await CoverArtArchive.frontCoverURL(forRelease: "mbid", session: StubSession.make())
    }

    @Test func httpImageURLIsUpgradedToHTTPS() async throws {
        let cover = try await frontCover(listing: coverArtListingJSON(image: "http://coverartarchive.org/release/mbid/1.jpg"))

        #expect(cover == "https://coverartarchive.org/release/mbid/1.jpg")
    }

    @Test func prefersThe1200pxThumbnail() async throws {
        let cover = try await frontCover(listing: coverArtListingJSON(
            image: "https://archive.example.com/original.jpg",
            thumbnails: [
                "500": "https://archive.example.com/500.jpg",
                "1200": "https://archive.example.com/1200.jpg",
            ]
        ))

        #expect(cover == "https://archive.example.com/1200.jpg")
    }

    @Test func fallsBackToTheOriginalWithoutA1200pxThumbnail() async throws {
        let cover = try await frontCover(listing: coverArtListingJSON(
            image: "https://archive.example.com/original.jpg",
            thumbnails: ["250": "https://archive.example.com/250.jpg", "500": "https://archive.example.com/500.jpg"]
        ))

        #expect(cover == "https://archive.example.com/original.jpg")
    }

    @Test func frontImageIsChosenOverEarlierOnes() async throws {
        let cover = try await frontCover(listing: coverArtListingJSON(images: [
            (image: "https://archive.example.com/back.jpg", front: false, thumbnails: [:]),
            (image: "https://archive.example.com/front.jpg", front: true, thumbnails: [:]),
        ]))

        #expect(cover == "https://archive.example.com/front.jpg")
    }

    @Test func firstImageIsUsedWhenNoneIsFront() async throws {
        let cover = try await frontCover(listing: coverArtListingJSON(images: [
            (image: "https://archive.example.com/back.jpg", front: false, thumbnails: [:]),
            (image: "https://archive.example.com/inner.jpg", front: false, thumbnails: [:]),
        ]))

        #expect(cover == "https://archive.example.com/back.jpg")
    }

    @Test func emptyListingHasNoCover() async throws {
        let cover = try await frontCover(listing: coverArtListingJSON(images: []))

        #expect(cover == nil)
    }
}
