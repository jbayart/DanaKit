import XCTest
import LoopKit
@testable import DanaProgress

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
        let reporter = DanaKitDoseProgressReporter(total: 2)
        let received = expectation(description: "Main queue notification")
        let observer = Observer { progressReporter in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(progressReporter.progress.deliveredUnits, 0.5)
            XCTAssertEqual(progressReporter.progress.percentComplete, 0.25)
            received.fulfill()
        }
        reporter.addObserver(observer)
        DispatchQueue.global().async { reporter.notify(deliveredUnits: 0.5) }
        wait(for: [received], timeout: 5)
        withExtendedLifetime(observer) {}
    }

    #if !DANA_BASELINE
    func testCustomReportingQueueIsRespected() {
        let reporter = DanaKitDoseProgressReporter(total: 2)
        let queue = DispatchQueue(label: "test.requested-reporting-queue")
        let key = DispatchSpecificKey<String>()
        queue.setSpecific(key: key, value: "requested")
        reporter.reportingQueue = queue
        let received = expectation(description: "Requested queue notification")
        let observer = Observer { _ in
            XCTAssertEqual(DispatchQueue.getSpecific(key: key), "requested")
            received.fulfill()
        }
        reporter.addObserver(observer)
        DispatchQueue.global().async { reporter.notify(deliveredUnits: 0.5) }
        wait(for: [received], timeout: 5)
        withExtendedLifetime(observer) {}
    }

    func testObserverCanReadProgressAndRemoveItself() {
        let reporter = DanaKitDoseProgressReporter(total: 2)
        let received = expectation(description: "Reentrant observer")
        let observer = Observer { progressReporter in
            XCTAssertEqual(progressReporter.progress.deliveredUnits, 1)
            received.fulfill()
        }
        reporter.addObserver(observer)
        let removingObserver = RemovingObserver(reporter)
        reporter.addObserver(removingObserver)
        DispatchQueue.global().async { reporter.notify(deliveredUnits: 1) }
        wait(for: [received, removingObserver.removed], timeout: 5)
        withExtendedLifetime((observer, removingObserver)) {}
    }

    func testConcurrentObserverChangesAndProgressUpdates() {
        let reporter = DanaKitDoseProgressReporter(total: 1000)
        let queue = DispatchQueue(label: "test.concurrent-reporting")
        reporter.reportingQueue = queue
        let observer = Observer { reporter in _ = reporter.progress }
        DispatchQueue.concurrentPerform(iterations: 1000) { index in
            switch index % 3 {
            case 0: reporter.addObserver(observer)
            case 1: reporter.removeObserver(observer)
            default: reporter.notify(deliveredUnits: Double(index))
            }
            _ = reporter.progress
        }
        queue.sync {}
        withExtendedLifetime(observer) {}
    }
    #endif
}

#if !DANA_BASELINE
final class RemovingObserver: DoseProgressObserver {
    let reporter: DanaKitDoseProgressReporter
    let removed = XCTestExpectation(description: "Observer removed without deadlock")
    init(_ reporter: DanaKitDoseProgressReporter) { self.reporter = reporter }
    func doseProgressReporterDidUpdate(_ reporter: DoseProgressReporter) {
        _ = reporter.progress
        reporter.removeObserver(self)
        removed.fulfill()
    }
}
#endif
