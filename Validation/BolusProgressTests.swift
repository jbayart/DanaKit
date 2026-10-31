import XCTest
import LoopKit
@testable import DanaProgress

#if DANA_BASELINE
typealias ProgressSource = DanaKitDoseProgressReporter
#else
typealias ProgressSource = DanaKitDoseProgressSource
#endif

final class Observer: DoseProgressObserver {
    let onUpdate: (DoseProgressReporter) -> Void
    init(_ onUpdate: @escaping (DoseProgressReporter) -> Void) {
        self.onUpdate = onUpdate
    }
    func doseProgressReporterDidUpdate(_ reporter: DoseProgressReporter) {
        onUpdate(reporter)
    }
}

final class BolusProgressTests: XCTestCase {
    func testBluetoothUpdateIsReportedOnMainThread() {
        let source = ProgressSource(total: 2)
        #if DANA_BASELINE
        let reporter: DoseProgressReporter = source
        #else
        let reporter = source.reporting(on: .main)
        #endif
        let received = expectation(description: "Main queue notification")
        let observer = Observer { actual in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(actual === reporter)
            XCTAssertEqual(actual.progress.deliveredUnits, 0.5)
            XCTAssertEqual(actual.progress.percentComplete, 0.25)
            received.fulfill()
        }
        reporter.addObserver(observer)
        DispatchQueue.global().async { source.notify(deliveredUnits: 0.5) }
        wait(for: [received], timeout: 5)
        withExtendedLifetime((observer, reporter)) {}
    }

    #if !DANA_BASELINE
    func testTwoReportersKeepIndependentQueues() {
        let source = ProgressSource(total: 2)
        let firstQueue = DispatchQueue(label: "test.first")
        let secondQueue = DispatchQueue(label: "test.second")
        let key = DispatchSpecificKey<String>()
        firstQueue.setSpecific(key: key, value: "first")
        secondQueue.setSpecific(key: key, value: "second")
        let first = source.reporting(on: firstQueue)
        let second = source.reporting(on: secondQueue)
        XCTAssertFalse(first === second)
        let firstReceived = expectation(description: "First queue")
        let secondReceived = expectation(description: "Second queue")
        firstReceived.expectedFulfillmentCount = 2
        secondReceived.expectedFulfillmentCount = 2
        let a = Observer { actual in
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), "first")
            XCTAssertTrue(actual === first)
            firstReceived.fulfill()
        }
        let b = Observer { actual in
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), "second")
            XCTAssertTrue(actual === second)
            secondReceived.fulfill()
        }
        first.addObserver(a)
        second.addObserver(b)
        source.notify(deliveredUnits: 0.5)
        firstQueue.sync {}
        secondQueue.sync {}
        source.notify(deliveredUnits: 1)
        wait(for: [firstReceived, secondReceived], timeout: 5)
        XCTAssertEqual(first.progress.deliveredUnits, 1)
        XCTAssertEqual(second.progress.deliveredUnits, 1)
        withExtendedLifetime((a, b, first, second)) {}
    }

    func testReporterStartsWithCurrentProgress() {
        let source = ProgressSource(total: 2)
        source.notify(deliveredUnits: 0.75)
        let reporter = source.reporting(on: .main)
        XCTAssertEqual(reporter.progress.deliveredUnits, 0.75)
        XCTAssertEqual(reporter.progress.percentComplete, 0.375)
    }

    func testObserverCanReadProgressAndRemoveItself() {
        let source = ProgressSource(total: 2)
        let reporter = source.reporting(on: .main)
        let observer = RemovingObserver()
        reporter.addObserver(observer)
        source.notify(deliveredUnits: 1)
        wait(for: [observer.removed], timeout: 5)
        source.notify(deliveredUnits: 2)
        XCTAssertEqual(reporter.progress.deliveredUnits, 2)
        withExtendedLifetime((observer, reporter)) {}
    }

    func testDestroyingOneReporterDoesNotAffectAnother() {
        let source = ProgressSource(total: 2)
        var released: DoseProgressReporter? = source.reporting(on: .main)
        weak var weakReporter = released
        released = nil
        XCTAssertNil(weakReporter)
        let reporter = source.reporting(on: .main)
        let received = expectation(description: "Remaining reporter")
        let observer = Observer { actual in
            XCTAssertEqual(actual.progress.deliveredUnits, 1)
            received.fulfill()
        }
        reporter.addObserver(observer)
        source.notify(deliveredUnits: 1)
        wait(for: [received], timeout: 5)
        withExtendedLifetime((observer, reporter)) {}
    }

    func testReporterKeepsSourceAlive() {
        var source: ProgressSource? = ProgressSource(total: 2)
        weak var weakSource = source
        var reporter: DoseProgressReporter? = source!.reporting(on: .main)
        source = nil
        XCTAssertNotNil(weakSource)
        XCTAssertEqual(reporter!.progress.deliveredUnits, 0)
        reporter = nil
        XCTAssertNil(weakSource)
    }

    func testConcurrentObserverChangesAndProgressUpdates() {
        let source = ProgressSource(total: 1000)
        let queue = DispatchQueue(label: "test.concurrent")
        let reporter = source.reporting(on: queue)
        let observer = Observer { actual in _ = actual.progress }
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            switch index % 3 {
            case 0: reporter.addObserver(observer)
            case 1: reporter.removeObserver(observer)
            default: source.notify(deliveredUnits: Double(index))
            }
            _ = reporter.progress
        }
        queue.sync {}
        withExtendedLifetime((observer, reporter)) {}
    }
    #endif
}

#if !DANA_BASELINE
final class RemovingObserver: DoseProgressObserver {
    let removed = XCTestExpectation(description: "Removed without deadlock")
    func doseProgressReporterDidUpdate(_ reporter: DoseProgressReporter) {
        _ = reporter.progress
        reporter.removeObserver(self)
        removed.fulfill()
    }
}
#endif
