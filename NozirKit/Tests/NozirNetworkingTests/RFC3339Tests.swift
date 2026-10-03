import Foundation
import Testing
@testable import NozirNetworking

/// 2026-10-03T11:31:09Z
private let wholeSecond = Date(timeIntervalSince1970: 1_791_027_069)

@Suite struct RFC3339Tests {
    @Test func parsesUTCWithoutFraction() {
        #expect(RFC3339.date(from: "2026-10-03T11:31:09Z") == wholeSecond)
    }

    // Jackson writes as many digits as the Instant has: 0, 3, 6 or 9.
    @Test(arguments: zip(
        [
            "2026-10-03T11:31:09.9Z",
            "2026-10-03T11:31:09.946Z",
            "2026-10-03T11:31:09.946123Z",
            "2026-10-03T11:31:09.946123456Z",
        ],
        [0.9, 0.946, 0.946123, 0.946123456]
    ))
    func parsesAnyNumberOfFractionalDigits(text: String, fraction: Double) throws {
        let date = try #require(RFC3339.date(from: text))
        #expect(abs(date.timeIntervalSince(wholeSecond) - fraction) < 0.000_001)
    }

    @Test func honoursAnOffset() {
        #expect(RFC3339.date(from: "2026-10-03T16:31:09+05:00") == wholeSecond)
    }

    @Test(arguments: ["", "yesterday", "2026-10-03", "2026-10-03T11:31:09.Z", "2026-10-03T11:31:09"])
    func rejectsWhatIsNotAnInstant(text: String) {
        #expect(RFC3339.date(from: text) == nil)
    }
}

@Suite struct NozirJSONTests {
    private struct Stamped: Decodable {
        let at: Date
    }

    @Test func decoderReadsServerInstants() throws {
        let json = Data(#"{"at":"2026-10-03T11:31:09.946123Z"}"#.utf8)
        let value = try NozirJSON.decoder().decode(Stamped.self, from: json)
        #expect(abs(value.at.timeIntervalSince1970 - 1_791_027_069.946123) < 0.000_001)
    }

    @Test func decoderRejectsSomethingThatIsNotAnInstant() {
        let json = Data(#"{"at":"soon"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try NozirJSON.decoder().decode(Stamped.self, from: json)
        }
    }
}
