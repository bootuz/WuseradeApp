import FirebaseFirestore
import FirebaseStorage
import XCTest
@testable import Wuserade

final class FirebasePhotoSubmissionStoreTests: XCTestCase {
    private func storageError(_ code: StorageErrorCode) -> NSError {
        NSError(domain: StorageErrorDomain, code: code.rawValue)
    }

    func testUnauthorizedUploadMeansBanned() {
        let mapped = FirebasePhotoSubmissionStore.mapped(storageError(.unauthorized))

        XCTAssertEqual(mapped as? PhotoSubmissionError, .banned)
    }

    func testTheSDKsUnauthorizedErrorMeansBanned() {
        let error = StorageError.unauthorized(bucket: "b", object: "o", serverError: [:])

        XCTAssertEqual(FirebasePhotoSubmissionStore.mapped(error) as? PhotoSubmissionError, .banned)
    }

    func testPermissionDeniedRecordMeansBanned() {
        let mapped = FirebasePhotoSubmissionStore.mapped(FirestoreErrorCode(.permissionDenied))

        XCTAssertEqual(mapped as? PhotoSubmissionError, .banned)
    }

    func testOtherErrorsPassThrough() {
        let errors: [NSError] = [
            NSError(domain: "elsewhere", code: 1),
            storageError(.objectNotFound),
            storageError(.unauthenticated),
            NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue),
            // The code alone decides nothing: it has to come with its own domain.
            NSError(domain: FirestoreErrorDomain, code: StorageErrorCode.unauthorized.rawValue),
            NSError(domain: StorageErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue),
        ]

        for error in errors {
            let mapped = FirebasePhotoSubmissionStore.mapped(error) as NSError
            XCTAssertEqual(mapped.domain, error.domain)
            XCTAssertEqual(mapped.code, error.code)
        }
    }

    func testTheSDKsOtherStorageErrorsPassThrough() {
        let errors: [StorageError] = [
            .objectNotFound(object: "o", serverError: [:]),
            .unauthenticated(serverError: [:]),
            .quotaExceeded(bucket: "b", serverError: [:]),
            .cancelled,
        ]

        for error in errors {
            let mapped = FirebasePhotoSubmissionStore.mapped(error)
            XCTAssertNil(mapped as? PhotoSubmissionError, "\(error)")
            XCTAssertEqual((mapped as NSError).code, (error as NSError).code)
        }
    }

    func testTheSDKsObjectNotFoundErrorIsNotFound() {
        XCTAssertTrue(FirebasePhotoSubmissionStore.isNotFound(StorageError.objectNotFound(object: "o", serverError: [:])))
        XCTAssertFalse(
            FirebasePhotoSubmissionStore.isNotFound(StorageError.unauthorized(bucket: "b", object: "o", serverError: [:]))
        )
    }

    // A send on a dead network must fail in about a minute, not the SDK's ten, so the sheet shows "try again".
    // The app has configured Firebase by the time its unit tests run.
    func testStorageGivesUpAfterAMinute() {
        let storage = FirebasePhotoSubmissionStore().storage

        XCTAssertEqual(storage.maxUploadRetryTime, 60)
        XCTAssertEqual(storage.maxOperationRetryTime, 60)
    }

    func testObjectNotFoundIsNotFound() {
        XCTAssertTrue(FirebasePhotoSubmissionStore.isNotFound(storageError(.objectNotFound)))
        XCTAssertFalse(FirebasePhotoSubmissionStore.isNotFound(storageError(.unauthorized)))
        XCTAssertFalse(
            FirebasePhotoSubmissionStore.isNotFound(NSError(domain: "elsewhere", code: StorageErrorCode.objectNotFound.rawValue))
        )
    }
}
