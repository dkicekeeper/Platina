#if canImport(Network)
import Foundation
import Testing
@testable import PSNKit

@Suite("Name resolution")
struct NameResolutionTests {
    /// What the resolution applied and remembered, in order.
    final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var _applied: [NameResolution.Mode] = []
        private var _remembered: [NameResolution.Mode] = []
        var applied: [NameResolution.Mode] { lock.withLock { _applied } }
        var remembered: [NameResolution.Mode] { lock.withLock { _remembered } }
        func apply(_ mode: NameResolution.Mode) { lock.withLock { _applied.append(mode) } }
        func remember(_ mode: NameResolution.Mode) { lock.withLock { _remembered.append(mode) } }
    }

    @Test("Starts with the remembered mode and applies it")
    func startsRemembered() async {
        let log = Log()
        let resolution = NameResolution(initial: .encrypted, apply: { log.apply($0) }, remember: { log.remember($0) })
        #expect(await resolution.mode == .encrypted)
        #expect(log.applied == [.encrypted])
    }

    @Test("A failure switches once; a failure from before the switch does not switch back")
    func switchesOnce() async {
        let log = Log()
        let resolution = NameResolution(initial: .system, apply: { log.apply($0) }, remember: { log.remember($0) })
        await resolution.failed(inTurn: 0)
        await resolution.failed(inTurn: 0)
        #expect(await resolution.mode == .encrypted)
        #expect(await resolution.turn == 1)
        #expect(log.applied == [.system, .encrypted])

        await resolution.failed(inTurn: 1)
        #expect(await resolution.mode == .system)
    }

    @Test("A success remembers its mode once, and only in the current turn")
    func remembersWhatWorked() async {
        let log = Log()
        let resolution = NameResolution(initial: .system, apply: { log.apply($0) }, remember: { log.remember($0) })
        await resolution.succeeded(inTurn: 0)
        #expect(log.remembered.isEmpty)

        await resolution.failed(inTurn: 0)
        await resolution.succeeded(inTurn: 0)
        #expect(log.remembered.isEmpty)
        await resolution.succeeded(inTurn: 1)
        await resolution.succeeded(inTurn: 1)
        #expect(log.remembered == [.encrypted])
    }

    @Test("A wrong address's failures switch; offline and cancelled do not")
    func whichFailures() {
        #expect(NameResolution.isWrongAddressLike(URLError(.secureConnectionFailed)))
        #expect(NameResolution.isWrongAddressLike(URLError(.cannotConnectToHost)))
        #expect(NameResolution.isWrongAddressLike(URLError(.timedOut)))
        #expect(!NameResolution.isWrongAddressLike(URLError(.notConnectedToInternet)))
        #expect(!NameResolution.isWrongAddressLike(URLError(.cancelled)))
    }
}
#endif
