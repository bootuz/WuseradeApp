import FirebaseFirestore
import FirebaseStorage
import Foundation
import Testing
@testable import Wuserade

struct FirebasePhotoSubmissionStoreTests {
    private static func storageError(_ code: StorageErrorCode) -> NSError {
        NSError(domain: StorageErrorDomain, code: code.rawValue)
    }

    @Test func `Unauthorized upload means banned`() {
        let mapped = FirebasePhotoSubmissionStore.mapped(Self.storageError(.unauthorized))

        #expect(mapped as? PhotoSubmissionError == .banned)
    }

    @Test func `The SDK's unauthorized error means banned`() {
        let error = StorageError.unauthorized(bucket: "b", object: "o", serverError: [:])

        #expect(FirebasePhotoSubmissionStore.mapped(error) as? PhotoSubmissionError == .banned)
    }

    @Test func `Permission denied record means banned`() {
        let mapped = FirebasePhotoSubmissionStore.mapped(FirestoreErrorCode(.permissionDenied))

        #expect(mapped as? PhotoSubmissionError == .banned)
    }

    @Test(arguments: [
        NSError(domain: "elsewhere", code: 1),
        storageError(.objectNotFound),
        storageError(.unauthenticated),
        NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue),
        // The code alone decides nothing: it has to come with its own domain.
        NSError(domain: FirestoreErrorDomain, code: StorageErrorCode.unauthorized.rawValue),
        NSError(domain: StorageErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue),
    ])
    func `Other errors pass through`(error: NSError) {
        let mapped = FirebasePhotoSubmissionStore.mapped(error) as NSError
        #expect(mapped.domain == error.domain)
        #expect(mapped.code == error.code)
    }

    @Test(arguments: [
        StorageError.objectNotFound(object: "o", serverError: [:]),
        .unauthenticated(serverError: [:]),
        .quotaExceeded(bucket: "b", serverError: [:]),
        .cancelled,
    ])
    func `The SDK's other storage errors pass through`(error: StorageError) {
        let mapped = FirebasePhotoSubmissionStore.mapped(error)
        #expect(mapped as? PhotoSubmissionError == nil, "\(error)")
        #expect((mapped as NSError).code == (error as NSError).code)
    }

    @Test func `The SDK's object not found error is not found`() {
        #expect(FirebasePhotoSubmissionStore.isNotFound(StorageError.objectNotFound(object: "o", serverError: [:])))
        #expect(
            !FirebasePhotoSubmissionStore.isNotFound(StorageError.unauthorized(bucket: "b", object: "o", serverError: [:]))
        )
    }

    // A send on a dead network must fail in about a minute, not the SDK's ten, so the sheet shows "try again".
    // The app has configured Firebase by the time its unit tests run.
    @Test func `Storage gives up after a minute`() {
        let storage = FirebasePhotoSubmissionStore().storage

        #expect(storage.maxUploadRetryTime == 60)
        #expect(storage.maxOperationRetryTime == 60)
    }

    @Test func `Object not found is not found`() {
        #expect(FirebasePhotoSubmissionStore.isNotFound(Self.storageError(.objectNotFound)))
        #expect(!FirebasePhotoSubmissionStore.isNotFound(Self.storageError(.unauthorized)))
        #expect(
            !FirebasePhotoSubmissionStore.isNotFound(NSError(domain: "elsewhere", code: StorageErrorCode.objectNotFound.rawValue))
        )
    }
}
