import XCTest
@testable import Wuserade

final class PhotoReportTests: XCTestCase {
    private func components(for poetName: String, poetID: Int) throws -> URLComponents {
        let url = AppLinks.photoReport(poetName: poetName, poetID: poetID)
        return try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    }

    func testReportIsAMailToTheOwner() throws {
        let report = try components(for: "Author 7", poetID: 7)
        let owner = try XCTUnwrap(URLComponents(url: AppLinks.email, resolvingAgainstBaseURL: false))
        XCTAssertEqual(report.scheme, "mailto")
        XCTAssertEqual(report.path, owner.path)
    }

    func testReportNamesThePoetInTheSubjectAndCarriesTheIDInTheBody() throws {
        let items = try XCTUnwrap(components(for: "Author 7", poetID: 7).queryItems)
        XCTAssertEqual(items.first { $0.name == "subject" }?.value, "\(OwnerCopy.reportSubject) Author 7 (7)")
        XCTAssertEqual(items.first { $0.name == "body" }?.value, "7")
    }

    func testPunctuationInTheNameSurvivesTheRoundTrip() throws {
        let items = try XCTUnwrap(components(for: "A&B+C=D", poetID: 9).queryItems)
        XCTAssertEqual(items.first { $0.name == "subject" }?.value, "\(OwnerCopy.reportSubject) A&B+C=D (9)")
    }
}
