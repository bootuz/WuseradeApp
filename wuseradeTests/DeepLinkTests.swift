// Minimum iOS 17.
//  The poem link a widget or the morning notification opens, and what opening it does.

import Foundation
import Testing
@testable import Wuserade

@MainActor
struct DeepLinkTests {
    @Test func `Round-trips a poem link`() throws {
        let url = DeepLink.poemURL(4130, source: "widget")
        #expect(url.absoluteString == "wuserade://poem/4130?source=widget")
        let link = try #require(DeepLink.poem(from: url))
        #expect(link.id == 4130)
        #expect(link.source == "widget")

        let tapped = try #require(DeepLink.poem(from: DeepLink.poemURL(7, source: "notification")))
        #expect(tapped.id == 7)
        #expect(tapped.source == "notification")
    }

    @Test func `A link without a known source still opens the poem`() throws {
        let bare = try #require(DeepLink.poem(from: URL(string: "wuserade://poem/12")!))
        #expect(bare.id == 12)
        #expect(bare.source == nil)

        let unknown = try #require(DeepLink.poem(from: URL(string: "wuserade://poem/12?source=elsewhere")!))
        #expect(unknown.id == 12)
        #expect(unknown.source == nil, "only widget and notification reach analytics")
    }

    @Test func `Rejects other links`() {
        let others = [
            "com.googleusercontent.apps.1234-abcd:/oauth2redirect?state=x&code=y",
            "wuserade://poem/abc",
            "wuserade://poem/",
            "wuserade://poem",
            "wuserade://poem/0",
            "wuserade://poem/-3",
            "wuserade://poem/12/extra",
            "wuserade://poet/12",
            "https://wuserade.app/poem/12",
        ]
        for string in others {
            let url = URL(string: string)!
            #expect(DeepLink.poem(from: url) == nil, "\(string)")
        }
    }

    @Test func `linkToMissingPoemOpensNothing`() async {
        struct Missing: Error {}
        var opened: [Poem] = []
        await PoemLinkOpener.open(id: 404, fetch: { _ in throw Missing() }, navigate: { opened.append($0) })
        #expect(opened.isEmpty)
    }

    @Test func `A link to a poem opens it`() async {
        let poem = Poem(id: 4130, title: "Гъатхэ", author: Author(id: 12, name: "Author 12"), content: "One\nTwo")
        var fetched: [Int] = []
        var opened: [Poem] = []
        await PoemLinkOpener.open(
            id: 4130,
            fetch: { id in fetched.append(id); return poem },
            navigate: { opened.append($0) }
        )
        #expect(fetched == [4130])
        #expect(opened == [poem])
    }

    @Test func `A notification's poem id becomes a notification link`() throws {
        // FCM data values are strings: the server sends `"poemId": str(id)`.
        let url = try #require(DeepLink.notificationURL(userInfo: ["poemId": "4130", "date": "2026-10-29"]))
        let link = try #require(DeepLink.poem(from: url))
        #expect(link.id == 4130)
        #expect(link.source == "notification")

        #expect(DeepLink.notificationURL(userInfo: ["poemId": 4130]) != nil, "a number is accepted too")
        #expect(DeepLink.notificationURL(userInfo: ["poemId": "abc"]) == nil)
        #expect(DeepLink.notificationURL(userInfo: ["date": "2026-10-29"]) == nil)
    }
}
