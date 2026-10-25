from pathlib import Path
import os, subprocess, sys
root = Path(sys.argv[1])
out = Path(sys.argv[2])
path = 'DanaKit/PumpManager/InteractiveBluetoothManager.swift'
ref = os.environ.get('DANA_SOURCE_REF')
source = subprocess.check_output(['git', '-C', str(root), 'show', ref + ':' + path], text=True) if ref else (root / path).read_text()
a = source.index('    func ensureConnected(')
b = source.index('    func writeMessage(', a)
methods = source[a:b]
# Compile the production methods verbatim; replace only the platform transport.
prefix = '''import Foundation

enum ConnectionResult {
    case success, timeout, busy, invalidBle5Keys
    case requestedPincode(String?)
    case failure(Error)
}
struct DanaGeneralKeepConnection {}
enum CommunicationType { case connection }
final class TestPumpManager {
    struct State { var bleIdentifier: String? = "pump" }
    var state = State()
    private let messages = Locked<[String]>(wrappedValue: [])
    var logCount: Int { messages.wrappedValue.count }
    func logDeviceCommunication(_ message: String, type: CommunicationType) {
        messages.mutate { $0.append(message) }
    }
}
final class TestLog {
    private let messages = Locked<[String]>(wrappedValue: [])
    var count: Int { messages.wrappedValue.count }
    func info(_ message: String) { messages.mutate { $0.append(message) } }
    func error(_ message: String) { messages.mutate { $0.append(message) } }
}
extension TimeInterval {
    static func seconds(_ value: Double) -> TimeInterval { value }
}

final class ConnectionHarness: @unchecked Sendable {
    @Locked var isBusy = false
    @Locked var connectionCallback: ((ConnectionResult) -> Void)?
    @Locked var connectionCompletion: ((ConnectionResult) -> Void)?
    @Locked var isConnected = false
    private let connections = Locked<[(ConnectionResult) -> Void]>(wrappedValue: [])
    var timoutCallback: DispatchWorkItem?
    var peripheral: String? = "pump"
    var pumpManager: TestPumpManager? = TestPumpManager()
    let managerQueue = DispatchQueue(label: "DanaKit.connection-test-timeouts")
    let log = TestLog()

    var connectionCount: Int { connections.wrappedValue.count }
    func connect(_ identifier: String, _ completion: @escaping (ConnectionResult) -> Void) {
        connections.mutate { $0.append(completion) }
    }
    func deliver(_ result: ConnectionResult, forConnection index: Int = 0) {
        let callback = connections.wrappedValue[index]
        callback(result)
    }
    func resetConnectionCompletion() { connectionCompletion = nil }
    func updateInitialState() {}
    func writeMessage(_ packet: DanaGeneralKeepConnection) throws -> Bool { true }
'''
# The original implementation still references its old result case.
if ref:
    prefix = prefix.replace('enum ConnectionResult {', 'enum ConnectionResult {\n    case alreadyConnectedAndBusy')
(out / 'ConnectionHarness.swift').write_text(prefix + methods + '\n}\n')
