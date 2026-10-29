import Foundation
import Testing
@testable import Wuserade

struct PhotoReportTests {
    private func components(for poetName: String, poetID: Int) throws -> URLComponents {
        let url = AppLinks.photoReport(poetName: poetName, poetID: poetID)
        return try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    @Test func `Report is a mail to the owner`() throws {
        let report = try components(for: "Author 7", poetID: 7)
        let owner = try #require(URLComponents(url: AppLinks.email, resolvingAgainstBaseURL: false))
        #expect(report.scheme == "mailto")
        #expect(report.path == owner.path)
    }

    @Test func `Report names the poet in the subject and carries the ID in the body`() throws {
        let items = try #require(components(for: "Author 7", poetID: 7).queryItems)
        #expect(items.first { $0.name == "subject" }?.value == "\(OwnerCopy.reportSubject) Author 7 (7)")
        #expect(items.first { $0.name == "body" }?.value == "7")
    }

    @Test func `Punctuation in the name survives the round trip`() throws {
        let items = try #require(components(for: "A&B+C=D", poetID: 9).queryItems)
        #expect(items.first { $0.name == "subject" }?.value == "\(OwnerCopy.reportSubject) A&B+C=D (9)")
    }
}
