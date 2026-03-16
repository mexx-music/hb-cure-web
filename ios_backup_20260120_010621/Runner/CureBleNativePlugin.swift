import Foundation
import Flutter
import UIKit
import CoreBluetooth

public class CureBleNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    // Channels
    private static let methodChannelName = "cure_ble_native/methods"
    private static let eventChannelName = "cure_ble_native/notify"

    private var eventSink: FlutterEventSink?

    // CoreBluetooth
    private var central: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var txChar: CBCharacteristic? // notify (TX from device)
    private var rxChar: CBCharacteristic? // write (RX to device)

    // Connect result completion (called when READY achieved)
    private var connectResult: FlutterResult?
    private var connectTimeoutWork: DispatchWorkItem?

    // Write queue / burst handling
    private var burstToken: Int = 0
    private var writeInFlight = false
    private let writeQueue = DispatchQueue(label: "cure.ble.write")

    // Line decoder
    private var incomingBuffer = ""

    // Pending command collector
    private class PendingRequest {
        let line: String
        let timeoutMs: Int
        var collected: [String] = []
        var token: String? = nil
        var tokenId: Int
        var completed = false
        var timeoutWork: DispatchWorkItem?
        let result: FlutterResult
        init(line: String, timeoutMs: Int, tokenId: Int, result: @escaping FlutterResult) {
            self.line = line
            self.timeoutMs = timeoutMs
            self.tokenId = tokenId
            self.result = result
        }
    }
    private var pendingRequest: PendingRequest?

    // UART UUIDs (Nordic NUS)
    private let UART_SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
    private let UART_RX_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e" // write
    private let UART_TX_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e" // notify

    override public init() {
        super.init()
        self.central = CBCentralManager(delegate: nil, queue: DispatchQueue.main)
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = CureBleNativePlugin()
        instance.central = CBCentralManager(delegate: instance, queue: DispatchQueue.main)

        let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - FlutterStreamHandler
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Method call handling
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "connect":
            self.handleConnect(call: call, result: result)
        case "disconnect":
            self.handleDisconnect(call: call, result: result)
        case "writeLine":
            self.handleWriteLine(call: call, result: result)
        case "sendCommandAndWaitLines":
            self.handleSendCommandAndWaitLines(call: call, result: result)
        case "buildUnlockResponse":
            self.handleBuildUnlockResponse(call: call, result: result)
        case "verifyDeviceSignature":
            self.handleVerifyDeviceSignature(call: call, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Helpers: emit events
    private func emitLine(line: String) {
        guard let sink = self.eventSink else { return }
        let map: [String: Any] = ["type": "line", "data": line]
        sink(map)
    }

    private func emitState(state: String, deviceId: String) {
        guard let sink = self.eventSink else { return }
        let map: [String: Any] = ["type": "state", "state": state, "deviceId": deviceId]
        sink(map)
    }

    private func emitError(message: String) {
        guard let sink = self.eventSink else { return }
        let map: [String: Any] = ["type": "error", "message": message]
        sink(map)
    }

    // MARK: - Method implementations (CoreBluetooth)
    private func handleConnect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        // Args may be String or Map with deviceId
        var deviceId: String? = nil
        if let args = call.arguments as? String {
            deviceId = args
        } else if let map = call.arguments as? [String: Any], let did = map["deviceId"] as? String {
            deviceId = did
        }

        // Guard central state
        guard central.state == .poweredOn else {
            result(FlutterError(code: "bluetooth_off", message: "Bluetooth not powered on", details: nil))
            return
        }

        // Reset previous session state to ensure clean start
        // Clear any pending command, incoming buffer and characteristic refs
        self.pendingRequest = nil
        self.incomingBuffer = ""
        self.txChar = nil
        self.rxChar = nil
        self.burstToken = 0
        self.writeInFlight = false
        // If already connected to a peripheral, cancel it first to avoid dirty state
        if let existing = self.connectedPeripheral {
            self.central.cancelPeripheralConnection(existing)
            self.connectedPeripheral = nil
        }

        // Keep the result to call when READY
        self.connectResult = result
        // Setup a connect timeout to fail if not READY within 12s
        self.connectTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.connectResult != nil {
                self.emitError(message: "connect timeout")
                self.connectResult?(FlutterError(code: "timeout", message: "connect timeout", details: nil))
                self.connectResult = nil
            }
        }
        self.connectTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: work)

        // If deviceId looks like UUID, try retrieve
        if let did = deviceId, let uuid = UUID(uuidString: did) {
            let peripherals = central.retrievePeripherals(withIdentifiers: [uuid])
            if let p = peripherals.first {
                self.startConnect(to: p)
                return
            }
            // fallthrough to scan
        }

        // Start scanning for UART service
        emitState(state: "SCANNING", deviceId: deviceId ?? "")
        central.scanForPeripherals(withServices: [CBUUID(string: UART_SERVICE_UUID)], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func startConnect(to peripheral: CBPeripheral) {
        self.emitState(state: "CONNECTING", deviceId: peripheral.identifier.uuidString)
        self.connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    private func handleDisconnect(call: FlutterMethodCall, result: @escaping FlutterResult) {
        DispatchQueue.main.async {
            if let p = self.connectedPeripheral {
                self.central.cancelPeripheralConnection(p)
            }
            self.connectedPeripheral = nil
            self.txChar = nil
            self.rxChar = nil
            // ensure any pending request is completed with partial data
            self.completePendingOnDisconnect()
            if let devId = call.arguments as? String {
                self.emitState(state: "DISCONNECTED", deviceId: devId)
            } else {
                self.emitState(state: "DISCONNECTED", deviceId: "")
            }
            result(nil)
        }
    }

    private func handleWriteLine(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let line = args["line"] as? String else {
            result(FlutterError(code: "bad_args", message: "writeLine requires {line:String}", details: nil))
            return
        }
        // Fire-and-forget write
        doEnqueueWrite(line: line)
        result(nil)
    }

    // MARK: - sendCommandAndWaitLines implementation
    private func handleSendCommandAndWaitLines(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let line = args["line"] as? String else {
            result(FlutterError(code: "bad_args", message: "sendCommandAndWaitLines requires {line:String, timeoutMs:int}", details: nil))
            return
        }
        let timeoutMs = (args["timeoutMs"] as? Int) ?? 5000

        // If pending exists -> BUSY
        if let _ = self.pendingRequest {
            result(FlutterError(code: "BUSY", message: "Another command is running", details: nil))
            return
        }

        guard let peripheral = self.connectedPeripheral, let _ = self.rxChar else {
            result(FlutterError(code: "NOT_CONNECTED", message: "Not connected", details: nil))
            return
        }

        // create pending
        let tokenId = (self.burstToken + 1)
        let pending = PendingRequest(line: line, timeoutMs: timeoutMs, tokenId: tokenId, result: result)
        self.pendingRequest = pending
        // schedule timeout: return partial collected if timeout occurs
        let timeoutWork = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if let pr = self.pendingRequest, pr.tokenId == tokenId {
                let out = pr.collected
                self.pendingRequest = nil
                // result with partial
                pr.result(out)
            }
        }
        pending.timeoutWork = timeoutWork
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeoutMs) / 1000.0, execute: timeoutWork)

        // enqueue write (this increments burstToken)
        doEnqueueWrite(line: line)

        // Note: we will call result(...) when we see OK/ERROR in incoming lines in handleIncomingLine
    }

    // MARK: - Incoming handling and line decoder
    private func handleIncomingLine(_ rawLine: String) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.isEmpty { return }

        // emit event
        emitLine(line: line)

        // if pending request exists, collect
        guard let pr = self.pendingRequest else { return }
        pr.collected.append(line)

        let firstToken = line.split { $0 == " " || $0 == "\t" }
            .first
            .map { String($0).uppercased() } ?? ""

        if firstToken == "OK" || firstToken == "ERROR" {
            pr.timeoutWork?.cancel()
            self.pendingRequest = nil
            let out = pr.collected
            DispatchQueue.main.async { pr.result(out) }
        }
    }

    // MARK: - Write enqueue with chunking & pacing
    private func doEnqueueWrite(line: String) {
        // increment burst token (cancel previous bursts)
        burstToken = burstToken &+ 1
        let myToken = burstToken

        let full = (line + "\r\n")
        guard let data = full.data(using: .utf8) else { return }

        // determine chunk size (max 20)
        var chunkSize = 20
        if let periph = connectedPeripheral {
            let mtu = periph.maximumWriteValueLength(for: .withoutResponse)
            if mtu <= 0 {
                chunkSize = 20
            } else {
                chunkSize = min(20, mtu)
            }
        }
        if chunkSize <= 0 { chunkSize = 20 }

        // pacing: choose per-chunk delay based on exact prefixes
        let perChunkDelayMs: Int = {
            if line.hasPrefix("sign=") { return 60 }
            if line.hasPrefix("response=") || line.hasPrefix("progAppend=") { return 45 }
            return 20
        }()

        // split into chunks
        var chunks: [Data] = []
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let sub = data.subdata(in: offset..<end)
            chunks.append(sub)
            offset = end
        }

        // schedule writes serially on writeQueue
        writeQueue.async { [weak self] in
            guard let self = self else { return }
            for (i, chunk) in chunks.enumerated() {
                // cancellation check
                if myToken != self.burstToken { return }
                DispatchQueue.main.async {
                    if let per = self.connectedPeripheral, let rx = self.rxChar {
                        per.writeValue(chunk, for: rx, type: .withoutResponse)
                    }
                }
                // sleep/pacing
                Thread.sleep(forTimeInterval: TimeInterval(perChunkDelayMs) / 1000.0)
            }
        }
    }

    // helper to complete pending request on disconnect
    private func completePendingOnDisconnect() {
        if let pr = self.pendingRequest {
            pr.timeoutWork?.cancel()
            self.pendingRequest = nil
            let out = pr.collected
            DispatchQueue.main.async { pr.result(out) }
        }
    }
}

// MARK: - CBCentralManagerDelegate & CBPeripheralDelegate
extension CureBleNativePlugin: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // emit state as needed
        switch central.state {
        case .poweredOn:
            // ready to scan
            break
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        // Connect to first discovered peripheral and stop scanning
        central.stopScan()
        startConnect(to: peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: UART_SERVICE_UUID)])
        emitState(state: "CONNECTED", deviceId: peripheral.identifier.uuidString)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        emitError(message: "connect failed: \(error?.localizedDescription ?? "unknown")")
        if let cb = self.connectResult {
            cb(FlutterError(code: "connect_failed", message: error?.localizedDescription, details: nil))
            self.connectResult = nil
        }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        emitState(state: "DISCONNECTED", deviceId: peripheral.identifier.uuidString)
        self.connectedPeripheral = nil
        self.rxChar = nil
        self.txChar = nil
        // ensure pending request completed
        self.completePendingOnDisconnect()
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let err = error { emitError(message: "discover services error: \(err.localizedDescription)") }
        guard let svcs = peripheral.services else { return }
        for s in svcs {
            if s.uuid == CBUUID(string: UART_SERVICE_UUID) {
                peripheral.discoverCharacteristics([CBUUID(string: UART_RX_UUID), CBUUID(string: UART_TX_UUID)], for: s)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let err = error { emitError(message: "discover chars error: \(err.localizedDescription)") }
        guard let chars = service.characteristics else { return }
        for c in chars {
            let uuid = c.uuid.uuidString.lowercased()
            if uuid == UART_RX_UUID { self.rxChar = c }
            if uuid == UART_TX_UUID { self.txChar = c }
        }
        // If both chars found, subscribe to notify on TX
        if let tx = self.txChar {
            peripheral.setNotifyValue(true, for: tx)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error { emitError(message: "notify state error: \(err.localizedDescription)") }
        if characteristic.uuid.uuidString.lowercased() == UART_TX_UUID {
            if characteristic.isNotifying {
                // READY
                emitState(state: "READY", deviceId: peripheral.identifier.uuidString)
                // fulfill connect result if pending
                if let cb = self.connectResult {
                    cb(nil)
                    self.connectResult = nil
                    self.connectTimeoutWork?.cancel()
                    self.connectTimeoutWork = nil
                }
            } else {
                // notifications turned off
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let err = error { emitError(message: "value update error: \(err.localizedDescription)") }
        guard let data = characteristic.value else { return }
        if let s = String(data: data, encoding: .utf8) {
            // append to buffer and split on newlines
            incomingBuffer += s
            while let range = incomingBuffer.range(of: "\n") {
                let line = String(incomingBuffer[..<range.lowerBound])
                // drop that part
                incomingBuffer = String(incomingBuffer[range.upperBound...])
                let cleaned = line.replacingOccurrences(of: "\r", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleaned.isEmpty {
                    handleIncomingLine(cleaned)
                }
            }
        }
    }
}

// MARK: - Crypto stubs (replace with secp256k1 SPM implementation)
// TODO: Add secp256k1 swift package and replace stubs below with real implementation.
extension CureBleNativePlugin {
    private func handleBuildUnlockResponse(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let challengeHex = args["challengeHex"] as? String else {
            result(FlutterError(code: "bad_args", message: "buildUnlockResponse requires {challengeHex:String}", details: nil))
            return
        }
        do {
            let sig = try CureCryptoIos.buildUnlockResponse(challengeHex: challengeHex)
            result(sig)
        } catch {
            // Map errors to FlutterError
            result(FlutterError(code: "CRYPTO_ERROR", message: "buildUnlockResponse failed: \(error)", details: nil))
        }
    }

    private func handleVerifyDeviceSignature(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let challengeHex = args["challengeHex"] as? String, let sigHex = args["sigHex"] as? String else {
            result(FlutterError(code: "bad_args", message: "verifyDeviceSignature requires {challengeHex:String, sigHex:String}", details: nil))
            return
        }
        let ok = CureCryptoIos.verifyDeviceSignature(challengeHex: challengeHex, sigHex: sigHex)
        result(ok)
    }
}
