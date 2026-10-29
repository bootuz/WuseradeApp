// Minimum iOS 17.
//  Which poets the signed-in reader has a photo waiting for, and sending a new one. `bind(uid:)` points it at an
//  account; the poet screens read it. Every status belongs to the bound account and is forgotten when that changes.

import Foundation
import Observation

@MainActor
@Observable
final class PhotoSubmissions {
    /// The account the statuses belong to. Nil until a reader is signed in with Apple or Google.
    private(set) var uid: String?

    private var statuses: [Int: WaitingStatus] = [:]
    /// The sends that have not finished. A send names its account too, so one that outlives a change of
    /// account never blocks the new account's.
    private var sending: Set<Sending> = []

    /// How many sends have succeeded for each poet. A check that began before one of them is stale when it
    /// returns: it may have read the record before the send wrote it.
    @ObservationIgnored private var successfulSends: [Int: Int] = [:]
    @ObservationIgnored private let store: any PhotoSubmissionStore
    @ObservationIgnored private let poetIDs: @MainActor () async throws -> [Int]

    private struct Sending: Hashable {
        let uid: String
        let poetID: Int
    }

    /// `poetIDs` lists every poet; `deleteAll` uses it to find the records an account could have.
    init(store: any PhotoSubmissionStore, poetIDs: @escaping @MainActor () async throws -> [Int]) {
        self.store = store
        self.poetIDs = poetIDs
    }

    /// The uid to bind for an account state: only an Apple or Google account can send photos.
    static func uid(for state: AccountState) -> String? {
        guard case let .signedIn(uid, _, _) = state else { return nil }
        return uid
    }

    /// Switches to `uid`, forgetting every status of the previous one. Binding the account that is
    /// already bound changes nothing.
    func bind(uid: String?) {
        guard uid != self.uid else { return }
        statuses = [:]
        self.uid = uid
    }

    func status(poetID: Int) -> WaitingStatus {
        statuses[poetID] ?? .unchecked
    }

    func isSending(poetID: Int) -> Bool {
        guard let uid else { return false }
        return sending.contains(Sending(uid: uid, poetID: poetID))
    }

    /// Asks whether a photo for the poet is waiting. A failed read is `.failed`, not an error. Does nothing
    /// without an account. Drops the answer if the account changed meanwhile, or if a send for the poet
    /// succeeded meanwhile (the send's `.waiting` is newer than what the check read).
    func check(poetID: Int) async {
        guard let uid else { return }
        let sendsBefore = successfulSends[poetID, default: 0]
        let status: WaitingStatus
        do {
            status = try await store.isWaiting(authorId: poetID, uid: uid) ? .waiting : .notWaiting
        } catch {
            status = .failed
        }
        guard self.uid == uid, successfulSends[poetID, default: 0] == sendsBefore else { return }
        statuses[poetID] = status
    }

    /// Sends the photo for the poet; on success it is `.waiting`. A failure is rethrown and leaves the
    /// status as it was. Ignored while a send for the same poet is still running.
    func send(_ jpeg: Data, for poetID: Int) async throws {
        guard let uid else { throw PhotoSubmissionError.notSignedIn }
        let sendingKey = Sending(uid: uid, poetID: poetID)
        guard sending.insert(sendingKey).inserted else { return }
        defer { sending.remove(sendingKey) }

        try await store.send(jpeg, authorId: poetID, uid: uid)
        successfulSends[poetID, default: 0] += 1
        if self.uid == uid { statuses[poetID] = .waiting }
    }

    /// Deletes the account's file and record for every poet, all at once, then forgets the statuses.
    /// Safe to run again after a failure. Takes the uid because it runs while the account is being deleted.
    func deleteAll(uid: String) async throws {
        let ids = try await poetIDs()
        let store = store
        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { try await store.delete(authorId: id, uid: uid) }
            }
            try await group.waitForAll()
        }
        statuses = [:]
    }
}
