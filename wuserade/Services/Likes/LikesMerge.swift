import Foundation

enum LikesMerge {
    /// The union of both lists by `poemId`. When both have the same poem, the like with the
    /// earlier `likedAt` wins (the existing one on a tie). Sorted newest first, then by
    /// descending `poemId` so the order is stable.
    static func merge(existing: [Like], incoming: [Like]) -> [Like] {
        var byPoem: [Int: Like] = [:]
        for like in existing + incoming {
            if let kept = byPoem[like.poemId], kept.likedAt <= like.likedAt { continue }
            byPoem[like.poemId] = like
        }
        return byPoem.values.sorted { ($0.likedAt, $0.poemId) > ($1.likedAt, $1.poemId) }
    }
}
