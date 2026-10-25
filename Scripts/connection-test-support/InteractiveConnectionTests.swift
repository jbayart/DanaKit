@testable import DanaConnectionHarness
import Foundation
import Testing

@Suite struct InteractiveConnectionTests {
    @Test(arguments: [false, true])
    func overlappingRequestDoesNotLoseFirstCompletion(scan: Bool) {
        let manager = ConnectionHarness()
        if scan { manager.peripheral = nil }
        var firstCalls = 0
        var secondWasRejected = false
        manager.ensureConnected { _ in firstCalls += 1 }
        manager.ensureConnected { result in
            if case .busy = result { secondWasRejected = true }
        }
        #expect(manager.connectionCount == 1)
        #expect(secondWasRejected)
        manager.deliver(.success)
        #expect(firstCalls == 1)
        #expect(!manager.isBusy)
    }

    @Test func requestRemainsBusyDuringItsCompletion() {
        let manager = ConnectionHarness()
        var rejected = false
        manager.ensureConnected { _ in
            #expect(manager.isBusy)
            manager.ensureConnected { result in
                if case .busy = result { rejected = true }
            }
        }
        manager.deliver(.success)
        #expect(rejected)
        #expect(manager.connectionCount == 1)
        #expect(!manager.isBusy)
    }

    @Test func lateConnectionResultCannotCompleteNextRequest() {
        let manager = ConnectionHarness()
        var firstCalls = 0
        var secondCalls = 0
        manager.ensureConnected { _ in firstCalls += 1 }
        manager.timoutCallback?.perform()
        #expect(firstCalls == 1)
        manager.ensureConnected { _ in secondCalls += 1 }
        manager.deliver(.success, forConnection: 0)
        #expect(firstCalls == 1)
        #expect(secondCalls == 0)
        #expect(manager.isBusy)
        manager.deliver(.success, forConnection: 1)
        #expect(secondCalls == 1)
        #expect(!manager.isBusy)
    }

    @Test(arguments: [false, true])
    func resultsAfterTimeoutDoNotLogOrCompleteAgain(scan: Bool) {
        let manager = ConnectionHarness()
        if scan { manager.peripheral = nil }
        var calls = 0
        manager.ensureConnected { _ in calls += 1 }
        manager.timoutCallback?.perform()
        #expect(calls == 1)
        let logCount = manager.log.count
        let communicationCount = manager.pumpManager?.logCount
        let lateResults: [ConnectionResult] = [
            .success,
            .failure(NSError(domain: "late", code: 1)),
            .requestedPincode(nil),
            .invalidBle5Keys
        ]
        for result in lateResults {
            manager.deliver(result)
        }
        #expect(manager.log.count == logCount)
        #expect(manager.pumpManager?.logCount == communicationCount)
        #expect(calls == 1)
    }

    @Test func connectionFailureReleasesRequest() {
        let manager = ConnectionHarness()
        var failed = false
        manager.ensureConnected { result in
            if case .failure = result { failed = true }
        }
        manager.deliver(.failure(NSError(domain: "test", code: 1)))
        #expect(failed)
        #expect(!manager.isBusy)
        manager.ensureConnected { _ in }
        #expect(manager.connectionCount == 2)
        manager.deliver(.success, forConnection: 1)
    }

    #if !DANA_BASELINE
    @Test func simultaneousRequestsStartOneConnection() {
        let manager = ConnectionHarness()
        let rejected = Counter()
        let completed = Counter()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            manager.ensureConnected { result in
                if case .busy = result { rejected.increment() }
                else { completed.increment() }
            }
        }
        #expect(manager.connectionCount == 1)
        #expect(rejected.value == 99)
        manager.deliver(.success)
        #expect(completed.value == 1)
    }

    @Test func timeoutAndSuccessCompleteOnce() throws {
        let manager = ConnectionHarness()
        let completed = Counter()
        manager.ensureConnected { _ in completed.increment() }
        let timeout = try #require(manager.timoutCallback)
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 { timeout.perform() }
            else { manager.deliver(.success) }
        }
        #expect(completed.value == 1)
        #expect(!manager.isBusy)
    }
    #endif
}

private final class Counter: @unchecked Sendable {
    private let count = Locked(wrappedValue: 0)
    func increment() { count.mutate { $0 += 1 } }
    var value: Int { count.wrappedValue }
}
