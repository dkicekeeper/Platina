import Foundation

/// You and a friend in one game you both have: each one's progress (0–100, as PSN weighs it)
/// and who is ahead. Friends are compared by progress only (the owner's decision, 2026-11-25).
public struct FriendComparison: Sendable, Hashable {
    public enum Leader: Sendable, Hashable {
        case me, friend, tie
    }

    public let mine: Int
    public let theirs: Int

    public init(mine: Int, theirs: Int) {
        self.mine = mine
        self.theirs = theirs
    }

    public var leader: Leader {
        mine > theirs ? .me : (theirs > mine ? .friend : .tie)
    }

    /// How far apart the two are, in percent.
    public var gap: Int { abs(mine - theirs) }

    /// The games both have (trophy list id → progress), compared; a game only one side has is
    /// left out.
    public static func shared(mine: [String: Int], theirs: [String: Int]) -> [String: FriendComparison] {
        var result: [String: FriendComparison] = [:]
        for (id, progress) in mine {
            if let other = theirs[id] {
                result[id] = FriendComparison(mine: progress, theirs: other)
            }
        }
        return result
    }
}

/// Where you stand against a friend over all the games you share.
public struct FriendStanding: Sendable, Hashable {
    public let ahead: Int
    public let behind: Int
    public let tied: Int

    public var shared: Int { ahead + behind + tied }

    public init(_ comparisons: some Sequence<FriendComparison>) {
        var ahead = 0, behind = 0, tied = 0
        for comparison in comparisons {
            switch comparison.leader {
            case .me: ahead += 1
            case .friend: behind += 1
            case .tie: tied += 1
            }
        }
        self.ahead = ahead
        self.behind = behind
        self.tied = tied
    }
}
