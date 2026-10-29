// Minimum iOS 17.
//  Reads waiting to be uploaded to an account, kept on the device so the "credential already in use" switch
//  never loses them. `AccountManager` uploads whatever is left here into the account it adopts.

import Foundation

struct PendingReadsStore {
    private static let key = "pendingReadsMerge"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func save(_ ids: Set<Int>) {
        guard !ids.isEmpty else {
            clear()
            return
        }
        defaults.set(ids.sorted(), forKey: Self.key)
    }

    /// The saved poem IDs, or an empty set when there are none.
    func load() -> Set<Int> {
        Set(defaults.array(forKey: Self.key) as? [Int] ?? [])
    }

    func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}
