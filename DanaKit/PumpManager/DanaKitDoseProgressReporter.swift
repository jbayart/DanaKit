import Foundation
import LoopKit

class DanaKitDoseProgressReporter: DoseProgressReporter {
    var progress: DoseProgress {
        lock.withLock {
            DoseProgress(deliveredUnits: deliveredUnits, percentComplete: deliveredUnits / total)
        }
    }

    @Locked var reportingQueue: DispatchQueue = .main

    private let lock = UnfairLock()
    private var observers = WeakSet<DoseProgressObserver>()

    private let total: Double
    private var deliveredUnits: Double = 0

    public init(total: Double) {
        self.total = total
    }

    public func addObserver(_ observer: DoseProgressObserver) {
        lock.withLock { observers.insert(observer) }
    }

    public func removeObserver(_ observer: DoseProgressObserver) {
        lock.withLock { observers.remove(observer) }
    }

    public func notify(deliveredUnits: Double) {
        let observersCopy = lock.withLock {
            self.deliveredUnits = deliveredUnits
            return observers
        }

        reportingQueue.async {
            for observer in observersCopy {
                observer.doseProgressReporterDidUpdate(self)
            }
        }
    }
}
