// Minimum iOS 17.
//  The widget's timeline: where it reads the day's document, when it refreshes, and what it shows of a poem.

import Foundation
import Testing
@testable import Wuserade

struct DailyProviderTests {
    /// `daily/2026-10-29` as Firestore's REST API returns it, in the shape `daily.py` writes: a poet without a
    /// photo has no `photoURL`, and `createdAt` is a server timestamp.
    private static let fixture = #"""
    {
      "name": "projects/wuserade/databases/(default)/documents/daily/2026-10-29",
      "fields": {
        "date": { "stringValue": "2026-10-29" },
        "poem": { "mapValue": { "fields": {
          "id": { "integerValue": "4130" },
          "title": { "stringValue": "Day title" },
          "authorId": { "integerValue": "12" },
          "authorName": { "stringValue": "Poet Twelve" },
          "text": { "stringValue": "Line one,\nLine two,\nLine three,\nLine four,\nLine five.\n\nSecond stanza" }
        } } },
        "shortPoem": { "mapValue": { "fields": {
          "id": { "integerValue": "77" },
          "title": { "stringValue": "" },
          "authorId": { "integerValue": "5" },
          "authorName": { "stringValue": "Poet Five" },
          "text": { "stringValue": "Short one\nShort two\nShort three" }
        } } },
        "poet": { "mapValue": { "fields": {
          "id": { "integerValue": "12" },
          "name": { "stringValue": "Poet Twelve" },
          "poemsCount": { "integerValue": "452" },
          "topPoems": { "arrayValue": { "values": [
            { "mapValue": { "fields": { "id": { "integerValue": "4130" }, "title": { "stringValue": "Day title" } } } },
            { "mapValue": { "fields": { "id": { "integerValue": "9" }, "title": { "stringValue": "Another" } } } }
          ] } }
        } } },
        "createdAt": { "timestampValue": "2026-10-22T03:00:00.123456Z" }
      },
      "createTime": "2026-10-22T03:00:00.123456Z",
      "updateTime": "2026-10-22T03:00:00.123456Z"
    }
    """#

    @Test func `REST URL for a date`() {
        #expect(
            DailyTimeline.restURL(date: "2026-10-29").absoluteString
                == "https://firestore.googleapis.com/v1/projects/wuserade/databases/(default)/documents/daily/2026-10-29"
        )
    }

    @Test func `Timeline refreshes at the next local midnight`() throws {
        let now = try Date("2026-10-29T20:00:00Z", strategy: .iso8601)
        let moscow = try #require(TimeZone(identifier: "Europe/Moscow"))
        let picks = try DailyTimeline.picks(fromREST: Data(Self.fixture.utf8))

        let entries = DailyTimeline.entries(for: picks, now: now, timeZone: moscow)

        #expect(entries.count == 2)
        #expect(entries[0].date == now)
        #expect(entries[0].picks == picks)
        #expect(entries[1].date == (try Date("2026-10-29T21:00:00Z", strategy: .iso8601)))
        #expect(entries[1].picks == nil, "the midnight entry carries nothing, so the widget reads the new day")
        #expect(DailyTimeline.nextMidnight(after: now, in: moscow) == entries[1].date)
    }

    @Test func `Without picks the timeline still ends at midnight`() throws {
        let now = try Date("2026-10-29T08:15:00Z", strategy: .iso8601)
        let utc = try #require(TimeZone(identifier: "UTC"))

        let entries = DailyTimeline.entries(for: nil, now: now, timeZone: utc)

        #expect(entries.map(\.date) == [now, try Date("2026-10-30T00:00:00Z", strategy: .iso8601)])
        #expect(entries.allSatisfy { $0.picks == nil })
    }

    @Test func `Decodes a real REST response fixture`() throws {
        let picks = try DailyTimeline.picks(fromREST: Data(Self.fixture.utf8))

        #expect(picks.date == "2026-10-29")
        #expect(picks.poem == DailyPoem(
            id: 4130, title: "Day title", authorId: 12, authorName: "Poet Twelve",
            text: "Line one,\nLine two,\nLine three,\nLine four,\nLine five.\n\nSecond stanza"
        ))
        #expect(picks.shortPoem.id == 77)
        #expect(picks.shortPoem.title.isEmpty)
        #expect(picks.poet.photoURL == nil)
        #expect(picks.poet.topPoems == [DailyPoemRef(id: 4130, title: "Day title"), DailyPoemRef(id: 9, title: "Another")])
    }

    @Test func `A document that is not a daily one does not decode`() {
        let error = #"{ "error": { "code": 404, "status": "NOT_FOUND" } }"#
        #expect(throws: (any Error).self) { try DailyTimeline.picks(fromREST: Data(error.utf8)) }
    }

    @Test func `The head shows the document's own day`() {
        #expect(DailyTimeline.dayAndMonth(of: "2026-10-29") == "29.10")
        #expect(DailyTimeline.dayAndMonth(of: "2027-01-05") == "05.01")
        #expect(DailyTimeline.dayAndMonth(of: "nonsense") == nil)
    }

    @Test func `Opening lines come from the first stanza only`() {
        let text = "Line one,\r\nLine two,\n  Line three\n\nSecond stanza"
        #expect(DailyTimeline.openingLines(of: text, limit: 4) == ["Line one,", "Line two,", "Line three"])
        #expect(DailyTimeline.openingLines(of: text, limit: 2) == ["Line one,", "Line two,"])
        #expect(DailyTimeline.openingLines(of: "\n\nAfter blank lines\nNext", limit: 4) == ["After blank lines", "Next"])
    }
}
