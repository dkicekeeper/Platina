import Testing
@testable import PlatinaCore

@Suite("Friend comparison")
struct FriendComparisonTests {
    @Test("Only the games both have are compared")
    func sharedOnly() {
        let shared = FriendComparison.shared(
            mine: ["A": 55, "B": 100, "C": 10],
            theirs: ["A": 80, "B": 100, "D": 40]
        )
        #expect(Set(shared.keys) == ["A", "B"])
        #expect(shared["A"] == FriendComparison(mine: 55, theirs: 80))
    }

    @Test("Who is ahead, and by how much")
    func leader() {
        #expect(FriendComparison(mine: 62, theirs: 80).leader == .friend)
        #expect(FriendComparison(mine: 62, theirs: 80).gap == 18)
        #expect(FriendComparison(mine: 90, theirs: 12).leader == .me)
        #expect(FriendComparison(mine: 100, theirs: 100).leader == .tie)
    }

    @Test("The standing over all shared games")
    func standing() {
        let standing = FriendStanding([
            FriendComparison(mine: 90, theirs: 10),
            FriendComparison(mine: 20, theirs: 30),
            FriendComparison(mine: 50, theirs: 50),
            FriendComparison(mine: 70, theirs: 60),
        ])
        #expect(standing.ahead == 2)
        #expect(standing.behind == 1)
        #expect(standing.tied == 1)
        #expect(standing.shared == 4)
    }

    @Test("No shared games, nothing to stand on")
    func empty() {
        #expect(FriendComparison.shared(mine: ["A": 1], theirs: [:]).isEmpty)
        #expect(FriendStanding([]).shared == 0)
    }
}
