// Minimum iOS 17.
//  The poems each account on this device has already written a read for, in UserDefaults under
//  `reads.known.<uid>`, so `ReadsController` writes each poem once. Forgotten when the account goes.

import Foundation

struct KnownReadsStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(uid: String) -> Set<Int> {
        Set(defaults.array(forKey: Self.key(uid)) as? [Int] ?? [])
    }

    func add(_ poemId: Int, uid: String) {
        var saved = load(uid: uid)
        guard saved.insert(poemId).inserted else { return }
        defaults.set(saved.sorted(), forKey: Self.key(uid))
    }

    /// Forgets everything `uid` read, once its reads are deleted or the account is gone.
    func remove(uid: String) {
        defaults.removeObject(forKey: Self.key(uid))
    }

    private static func key(_ uid: String) -> String {
        "reads.known.\(uid)"
    }
}
