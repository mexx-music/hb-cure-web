import Foundation
import Flutter
import UIKit
import CoreBluetooth

public final class CureBleNativePlugin: NSObject, FlutterPlugin, FlutterStreamHandler, CBPeripheralDelegate, CBCentralManagerDelegate {

  // Retain plugin instance to avoid early deallocation which can drop CBCentralManager delegate callbacks
  private static var retainedInstance: CureBleNativePlugin? = nil

  // Channels
  private static let methodChannelName = "cure_ble_native/methods"
  private static let eventChannelName  = "cure_ble_native/notify"

  private var eventSink: FlutterEventSink?

  // Buffer early logs produced before Flutter starts listening (to avoid losing connect logs)
  private var earlyLines: [String] = []
  private let earlyLinesMax = 200

  // Nordic UART Service (NUS)
  private let UART_SERVICE_UUID = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
  private let UART_RX_UUID      = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e") // write
  private let UART_TX_UUID      = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e") // notify

  // BLE
  private var central: CBCentralManager!
  private var peripheral: CBPeripheral?
  private var rxChar: CBCharacteristic?
  private var txChar: CBCharacteristic?

  // Connect lifecycle
  private var connectResult: FlutterResult?
  private var connectTimeoutWork: DispatchWorkItem?
  private var connectRequestedId: String?

  // Incoming line decoder
  private var rxBytesBuffer = Data()

  // Write burst / pacing
  private var burstToken: Int = 0
  private var pendingChunks: [Data] = []
  private var pendingWriteType: CBCharacteristicWriteType = .withoutResponse
  private var pendingDelayMs: Int = 20
  private var sending: Bool = false

  // For WR: we keep this for diagnostics, but we no longer *depend* on didWrite
  private var awaitingDidWrite: Bool = false

  // Target characteristic for the current burst (we always use RX for writes)
  private var writeTargetChar: CBCharacteristic? = nil

  // Debug: capture last 64-hex challenge seen on wire
  private var lastChallengeFromWire: String?

  // Pending request for sendCommandAndWaitLines
  private final class PendingRequest {
    let line: String
    let timeoutMs: Int
    let result: FlutterResult
    var collected: [String] = []
    var completed: Bool = false
    var timeoutWork: DispatchWorkItem?

    init(line: String, timeoutMs: Int, result: @escaping FlutterResult) {
      self.line = line
      self.timeoutMs = timeoutMs
      self.result = result
    }
  }
  private var pending: PendingRequest?

  // MARK: - Helpers

  private func stateName(_ state: CBManagerState) -> String {
    switch state {
    case .unknown: return "unknown"
    case .resetting: return "resetting"
    case .unsupported: return "unsupported"
    case .unauthorized: return "unauthorized"
    case .poweredOff: return "poweredOff"
    case .poweredOn: return "poweredOn"
    @unknown default: return "future"
    }
  }

  private func ensureCentralInitialized() {
    guard central == nil else { return }

    central = CBCentralManager(delegate: self, queue: DispatchQueue.main)

    let sRaw = central.state.rawValue
    let sName = stateName(central.state)

    emitLine("IOS_CENTRAL_CREATED name=\(sName) raw=\(sRaw)")
    emitLine("IOS_CENTRAL_CREATED_INFO eventSinkNil=\(eventSink == nil) earlyLinesCount=\(earlyLines.count)")

    if let cent = central {
      print("IOS_CENTRAL_CREATED_PTR centralPtr=\(Unmanaged.passUnretained(cent).toOpaque()) state=\(sName)")
    } else {
      print("IOS_CENTRAL_CREATED_PTR centralPtr=nil")
    }
  }

  // MARK: - FlutterPlugin

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = CureBleNativePlugin()

    // Plugin build marker (diagnostic): confirms this Swift file/version is compiled into the app
    instance.emitLine("IOS_PLUGIN_BUILD_MARKER_HBCURE_001")

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methodChannel)

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: registrar.messenger()
    )
    eventChannel.setStreamHandler(instance)

    // Retain instance for process lifetime
    CureBleNativePlugin.retainedInstance = instance
  }

  // MARK: - StreamHandler

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events

    // Diagnostic: report entering onListen and how many early lines will be flushed
    emitLine("IOS_ONLISTEN entering earlyLinesCount=\(earlyLines.count) eventSinkNil=\(eventSink == nil)")

    // Plugin build marker (diagnostic): confirm onListen executed
    emitLine("IOS_PLUGIN_BUILD_MARKER_HBCURE_002")

    // IMPORTANT: create CBCentralManager only now, after EventChannel is ready
    ensureCentralInitialized()

    // Flush any early buffered lines so Flutter receives logs produced before onListen
    if !earlyLines.isEmpty {
      let flushed = earlyLines.count
      emitLine("IOS_ONLISTEN_FLUSHED count=\(flushed)")
      print("IOS_ONLISTEN_FLUSH console_flushed=\(flushed)")

      for l in earlyLines {
        events(["type": "line", "data": l])
      }
      earlyLines.removeAll()
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil
    return nil
  }

  // --- Helper: Event + Arg utilities ---
  private func emitLine(_ line: String) {
    if let sink = eventSink {
      sink(["type": "line", "data": line])
    } else {
      earlyLines.append(line)
      if earlyLines.count > earlyLinesMax {
        earlyLines.removeFirst(earlyLines.count - earlyLinesMax)
      }
      print("IOS_BUFFERED_LINE count=\(earlyLines.count) buffered=\(line)")
      print(line)
    }
  }

  private func emitState(_ state: String, deviceId: String) {
    eventSink?(["type": "state", "state": state, "deviceId": deviceId])
  }

  private func emitError(_ msg: String) {
    eventSink?(["type": "error", "message": msg])
  }

  private func extractString(_ args: Any?, key: String) -> String? {
    if let s = args as? String { return s }
    if let m = args as? [String: Any], let v = m[key] as? String { return v }
    return nil
  }

  private func extractInt(_ args: Any?, key: String) -> Int? {
    if let m = args as? [String: Any] {
      if let v = m[key] as? Int { return v }
      if let n = m[key] as? NSNumber { return n.intValue }
    }
    return nil
  }

  // MARK: - MethodChannel

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    emitLine("IOS_METHOD \(call.method)")
    emitLine("IOS_METHOD \(call.method) args=\(String(describing: call.arguments))")

    switch call.method {
    case "connect":
      let deviceId = extractString(call.arguments, key: "deviceId")
      handleConnect(deviceId: deviceId, result: result)

    case "disconnect":
      handleDisconnect()
      result(nil)

    case "writeLine":
      guard let line = extractString(call.arguments, key: "line") else {
        result(FlutterError(code: "bad_args", message: "writeLine requires {line:String}", details: nil))
        return
      }
      guard isReady else {
        result(FlutterError(code: "NOT_CONNECTED", message: "Not connected", details: nil))
        return
      }
      enqueueWrite(line: line)
      result(nil)

    case "sendCommandAndWaitLines":
      guard let line = extractString(call.arguments, key: "line") else {
        result(FlutterError(code: "bad_args", message: "sendCommandAndWaitLines requires {line:String, timeoutMs:int}", details: nil))
        return
      }
      let timeoutMs = extractInt(call.arguments, key: "timeoutMs") ?? 5000
      handleSendCommandAndWaitLines(line: line, timeoutMs: timeoutMs, result: result)

    case "stopScan":
      emitLine("IOS_METHOD stopScan requested")
      instanceStopScan()
      result(nil)

    case "buildUnlockResponse":
      guard let challengeHex = extractString(call.arguments, key: "challengeHex") else {
        result(FlutterError(code: "bad_args", message: "buildUnlockResponse requires {challengeHex:String}", details: nil))
        return
      }
      do {
        let sig = try CureCryptoIos.buildUnlockResponse(challengeHex: challengeHex)
        emitLine("IOS_SIG challenge=\(challengeHex) sig=\(sig)")

        let sigRaw = sig.trimmingCharacters(in: .whitespacesAndNewlines)
        var fixed = sigRaw.lowercased()
        if fixed.count == 130 {
          fixed = String(fixed.dropFirst(2))
        }
        emitLine("IOS_SIG_LEN hex=\(sigRaw.count)->\(fixed.count) bytes=\(sigRaw.count/2)->\(fixed.count/2)")
        result(fixed)
      } catch {
        emitLine("IOS_SIG_ERROR \(error)")
        result(FlutterError(code: "CRYPTO_ERROR", message: "buildUnlockResponse failed: \(error)", details: nil))
      }

    case "verifyDeviceSignature":
      guard let challengeHex = extractString(call.arguments, key: "challengeHex"),
            let sigHex = extractString(call.arguments, key: "sigHex") else {
        result(FlutterError(code: "bad_args", message: "verifyDeviceSignature requires {challengeHex:String, sigHex:String}", details: nil))
        return
      }
      let ok = CureCryptoIos.verifyDeviceSignature(challengeHex: challengeHex, sigHex: sigHex)
      result(ok)

    case "getCentralState":
      let sName: String
      if central == nil {
        sName = "unknown"
      } else {
        sName = stateName(central.state)
      }
      emitLine("IOS_METHOD getCentralState result=\(sName)")
      result(sName)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Connect / Disconnect

  private func handleConnect(deviceId: String?, result: @escaping FlutterResult) {
    ensureCentralInitialized()

    guard central.state == .poweredOn else {
      emitLine("IOS_SCAN_BLOCKED state=\(central.state.rawValue)")
      self.connectResult = result
      self.connectRequestedId = deviceId
      emitError("Bluetooth not powered on")
      return
    }

    self.connectResult = result
    self.connectRequestedId = deviceId
    self.rxBytesBuffer = Data()
    self.rxChar = nil
    self.txChar = nil
    self.peripheral = nil
    self.lastChallengeFromWire = nil
    self.completePendingOnDisconnect()

    self.connectTimeoutWork?.cancel()
    let work = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      if self.connectResult != nil {
        self.emitError("connect timeout")
        self.connectResult?(FlutterError(code: "timeout", message: "connect timeout", details: nil))
        self.connectResult = nil
      }
    }
    self.connectTimeoutWork = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 12.0, execute: work)

    if let did = deviceId, let uuid = UUID(uuidString: did) {
      let found = central.retrievePeripherals(withIdentifiers: [uuid])
      if let p = found.first {
        startConnect(to: p)
        return
      }
    }

    emitState("SCANNING", deviceId: deviceId ?? "")
    emitLine("IOS_SCAN_REQUESTED service=nil (scan all) state=\(central.state.rawValue)")
    central.scanForPeripherals(withServices: nil,
                               options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
  }

  private func startConnect(to p: CBPeripheral) {
    self.peripheral = p
    p.delegate = self
    emitLine("IOS_DELEGATE_SET peripheral=\(p.identifier)")
    emitState("CONNECTING", deviceId: p.identifier.uuidString)
    central.connect(p, options: nil)
  }

  private func handleDisconnect() {
    if let p = peripheral {
      central.cancelPeripheralConnection(p)
    }
    peripheral = nil
    rxChar = nil
    txChar = nil
    rxBytesBuffer = Data()
    lastChallengeFromWire = nil
    completePendingOnDisconnect()
  }

  private var isReady: Bool {
    return peripheral?.state == .connected && rxChar != nil && txChar != nil
  }

  // MARK: - sendCommandAndWaitLines

  private func handleSendCommandAndWaitLines(line: String, timeoutMs: Int, result: @escaping FlutterResult) {
    guard isReady else {
      result(FlutterError(code: "NOT_CONNECTED", message: "Not connected", details: nil))
      return
    }
    if let pr = pending, !pr.completed {
      result(FlutterError(code: "BUSY", message: "Another command is running", details: nil))
      return
    }

    let pr = PendingRequest(line: line, timeoutMs: timeoutMs, result: result)
    pending = pr

    let tw = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      guard let cur = self.pending, cur === pr, !cur.completed else { return }
      cur.completed = true
      self.pending = nil
      cur.result(cur.collected)
    }
    pr.timeoutWork = tw
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeoutMs)/1000.0, execute: tw)

    // Minimal change: remove the old two-line response hack and send the full line as one logical command
    enqueueWrite(line: line)
  }

  private func completePendingOnDisconnect() {
    if let pr = pending, !pr.completed {
      pr.timeoutWork?.cancel()

      if !rxBytesBuffer.isEmpty {
        while let lfRange = rxBytesBuffer.firstRange(of: Data([0x0A])) {
          var lineData = rxBytesBuffer.subdata(in: 0..<lfRange.lowerBound)
          rxBytesBuffer.removeSubrange(0..<lfRange.upperBound)
          if lineData.last == 0x0D { lineData.removeLast() }
          if let s = String(data: lineData, encoding: .utf8) {
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { pr.collected.append(cleaned) }
          } else {
            let hex = lineData.map { String(format: "%02x", $0) }.joined()
            pr.collected.append(hex)
          }
        }
        if !rxBytesBuffer.isEmpty {
          if let s = String(data: rxBytesBuffer, encoding: .utf8) {
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { pr.collected.append(cleaned) }
          } else {
            let hex = rxBytesBuffer.map { String(format: "%02x", $0) }.joined()
            pr.collected.append(hex)
          }
          rxBytesBuffer.removeAll()
        }
      }

      pr.completed = true
      pending = nil
      pr.result(pr.collected)
    }
  }

  // MARK: - Write

  private func enqueueWrite(line: String) {
    guard let p = peripheral, let rx = rxChar else { return }

    let fullLine = line + "\r\n"
    guard let payloadData = fullLine.data(using: .utf8) else { return }

    let propsRaw = rx.properties.rawValue
    let hasWNR = (propsRaw & CBCharacteristicProperties.writeWithoutResponse.rawValue) != 0
    let hasWR  = (propsRaw & CBCharacteristicProperties.write.rawValue) != 0

    emitLine("IOS_RX_PROPS_RAW \(propsRaw)")
    emitLine("IOS_MASK_WNR \(CBCharacteristicProperties.writeWithoutResponse.rawValue) IOS_MASK_WR \(CBCharacteristicProperties.write.rawValue)")
    emitLine("IOS_RX_HAS_WNR \(hasWNR) IOS_RX_HAS_WR \(hasWR)")

    // Determine if this is a response=<sig> command
    let isResponse = line.hasPrefix("response=")

    // Force response to use withResponse (WR) to match Android parity
    let candidateWriteType: CBCharacteristicWriteType
    if isResponse {
      candidateWriteType = .withResponse
    } else if hasWR {
      candidateWriteType = .withResponse
    } else if hasWNR {
      candidateWriteType = .withoutResponse
    } else {
      emitError("RX char not writable")
      return
    }
    pendingWriteType = candidateWriteType

    let wtStr = candidateWriteType == .withoutResponse ? "WNR" : "WR"
    emitLine("IOS_WRITE \(line)")
    emitLine("IOS_WRITE_META supportsWwr=\(hasWNR) supportsWr=\(hasWR) writeType=\(wtStr) payloadBytes=\(payloadData.count)")

    let maxLenWR  = p.maximumWriteValueLength(for: .withResponse)
    let maxLenWNR = p.maximumWriteValueLength(for: .withoutResponse)
    emitLine("IOS_WR_MAXLEN_WR \(maxLenWR) WNR \(maxLenWNR)")

    // For response payloads we always chunk to 20 bytes (conservative Android-like behavior)
    let isResponseLine = isResponse
    pendingDelayMs = isResponseLine ? 250 : 10
    let delayMs = pendingDelayMs

    var chunks: [Data] = []
    if isResponseLine {
      let chunkSize = 20
      var offset = 0
      while offset < payloadData.count {
        let end = min(offset + chunkSize, payloadData.count)
        chunks.append(payloadData.subdata(in: offset..<end))
        offset = end
      }
      emitLine("IOS_WRITE_CHUNKING_RESPONSE chunkSize=\(chunkSize) total=\(chunks.count) delayMs=\(delayMs)")
    } else {
      let maxLen = (candidateWriteType == .withResponse) ? maxLenWR : maxLenWNR
      if maxLen > 0 && payloadData.count <= maxLen {
        chunks = [payloadData]
      } else {
        let chunkSize = max(1, min(maxLen > 0 ? Int(maxLen) : 20, payloadData.count))
        var offset = 0
        while offset < payloadData.count {
          let end = min(offset + chunkSize, payloadData.count)
          chunks.append(payloadData.subdata(in: offset..<end))
          offset = end
        }
      }
    }

    emitLine("IOS_WRITE_SPLIT chunks=\(chunks.count) delayMs=\(delayMs)")

    writeTargetChar = rx
    emitLine("IOS_WRITE_TARGET uuid=\(writeTargetChar?.uuid.uuidString ?? "nil")")

    peripheral?.delegate = self
    emitLine("IOS_SET_DELEGATE_BEFORE_BURST delegate=\(String(describing: peripheral?.delegate)) self=\(type(of: self))")

    startBurst(chunks: chunks, writeType: candidateWriteType, delayMs: delayMs)
  }

  // MARK: - Burst sender

  private func sendNextChunk(token: Int) {
    let wtLabel = (pendingWriteType == .withResponse) ? "WR" : "WNR"
    emitLine("IOS_BUILD_MARKER_2026_02_19 sendNextChunk entered writeType=\(wtLabel)")

    guard sending else { return }
    guard token == burstToken else { return }
    guard let p = peripheral, let target = writeTargetChar ?? rxChar else { return }

    if pendingChunks.isEmpty {
      sending = false
      emitLine("IOS_WRITE_DONE")
      return
    }

    if pendingWriteType == .withoutResponse {
      var sentNow = 0
      while !pendingChunks.isEmpty && p.canSendWriteWithoutResponse {
        let chunk = pendingChunks.removeFirst()
        sentNow += 1
        emitLine("IOS_WRITE_CHUNK len=\(chunk.count) type=WNR remaining=\(pendingChunks.count)")
        p.delegate = self
        p.writeValue(chunk, for: target, type: .withoutResponse)
      }
      if pendingChunks.isEmpty {
        sending = false
        emitLine("IOS_WRITE_DONE")
        return
      }
      emitLine("IOS_WNR_BLOCKED remaining=\(pendingChunks.count) sentNow=\(sentNow)")
      return
    }

    if pendingWriteType == .withResponse {
      // WR: send one chunk and strictly wait for didWriteValueFor to advance.
      // Schedule a watchdog that will ADVANCE the burst (fallback) if no ACK arrives
      // (we avoid an immediate abort because some iOS/firmware combos never deliver
      // didWrite callbacks reliably; fallback preserves progress and mirrors older behavior).
      let chunk = pendingChunks.removeFirst()
      awaitingDidWrite = true
      emitLine("IOS_WRITE_CHUNK len=\(chunk.count) type=WR remaining=\(pendingChunks.count)")
      p.delegate = self
      p.writeValue(chunk, for: target, type: .withResponse)

      // Watchdog: if no didWrite callback arrives within timeout, advance the burst (do not abort).
      let myToken = token
      let delaySec = Double(max(10, pendingDelayMs)) / 1000.0
      DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
        guard let self = self else { return }
        guard self.sending, self.burstToken == myToken else { return }
        guard self.awaitingDidWrite else { return }

        // Fallback-advance: log and continue with next chunk (do not abort entire burst).
        self.emitLine("IOS_WR_WATCHDOG_ADVANCE token=\(myToken) remaining=\(self.pendingChunks.count)")
        self.awaitingDidWrite = false
        self.sendNextChunk(token: myToken)
      }
      return
    }
  }

  public func peripheral(_ peripheral: CBPeripheral,
                         didWriteValueFor characteristic: CBCharacteristic,
                         error: Error?) {
    emitLine("IOS_DIDWRITE uuid=\(characteristic.uuid.uuidString) err=\(String(describing: error))")

    if let e = error {
      emitError("write error: \(e.localizedDescription)")
      awaitingDidWrite = false
      return
    }

    awaitingDidWrite = false
    let token = burstToken
    DispatchQueue.main.async { [weak self] in
      self?.sendNextChunk(token: token)
    }
  }

  // MARK: - CBCentralManagerDelegate / CBPeripheralDelegate

  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    let sRaw = central.state.rawValue
    let sName = stateName(central.state)

    let eventSinkWasNil = (eventSink == nil)
    print("IOS_CENTRAL_DID_UPDATE_STATE centralPtr=\(Unmanaged.passUnretained(central).toOpaque()) name=\(sName) raw=\(sRaw) eventSinkNil=\(eventSinkWasNil) earlyLinesBefore=\(earlyLines.count)")

    emitLine("IOS_CENTRAL_STATE name=\(sName) raw=\(sRaw)")

    if eventSink == nil {
      print("IOS_CENTRAL_STATE_BUFFERED name=\(sName) earlyLinesAfter=\(earlyLines.count)")
    } else {
      print("IOS_CENTRAL_STATE_SENT name=\(sName) earlyLinesAfter=\(earlyLines.count)")
    }

    emitLine("IOS_CENTRAL_STATE_DBG eventSinkNil=\(eventSink == nil) earlyLinesCount=\(earlyLines.count)")

    if central.state == .poweredOn {
      emitLine("IOS_CENTRAL_POWERED_ON_REACHED")
      print("IOS_CENTRAL_POWERED_ON_REACHED centralPtr=\(Unmanaged.passUnretained(central).toOpaque())")
      if let did = connectRequestedId, connectResult != nil {
        emitLine("IOS_CENTRAL_POWERED_ON retryConnect id=\(did)")
        handleConnect(deviceId: did, result: connectResult!)
      }
    }
  }

  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    emitLine("IOS_DID_CONNECT \(peripheral.identifier.uuidString)")
    connectTimeoutWork?.cancel()
    connectTimeoutWork = nil

    self.peripheral = peripheral
    peripheral.delegate = self

    emitState("CONNECTED", deviceId: peripheral.identifier.uuidString)
    peripheral.discoverServices([UART_SERVICE_UUID])
  }

  public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
    emitLine("IOS_DID_FAIL_CONNECT \(peripheral.identifier.uuidString) err=\(String(describing: error))")
    connectTimeoutWork?.cancel()
    connectTimeoutWork = nil

    connectResult?(FlutterError(code: "connect_failed", message: "didFailToConnect", details: "\(String(describing: error))"))
    connectResult = nil
  }

  public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
    emitLine("IOS_DID_DISCONNECT \(peripheral.identifier.uuidString) err=\(String(describing: error))")
    emitState("DISCONNECTED", deviceId: peripheral.identifier.uuidString)

    self.peripheral = nil
    self.rxChar = nil
    self.txChar = nil
    self.rxBytesBuffer.removeAll()
    self.lastChallengeFromWire = nil

    completePendingOnDisconnect()
  }

  // MARK: - CBPeripheralDelegate

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    if let e = error {
      emitLine("IOS_DISCOVER_SERVICES_ERR \(e.localizedDescription)")
      return
    }
    emitLine("IOS_SERVICES \(peripheral.services?.count ?? 0)")

    guard let services = peripheral.services else { return }
    for s in services where s.uuid == UART_SERVICE_UUID {
      emitLine("IOS_UART_SERVICE_FOUND")
      peripheral.discoverCharacteristics([UART_RX_UUID, UART_TX_UUID], for: s)
      return
    }
    emitLine("IOS_UART_SERVICE_MISSING")
  }

  public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
    if let e = error {
      emitLine("IOS_DISCOVER_CHARS_ERR \(e.localizedDescription)")
      return
    }
    guard let chars = service.characteristics else { return }
    emitLine("IOS_CHARS \(chars.count)")

    for c in chars {
      if c.uuid == UART_RX_UUID { rxChar = c; emitLine("IOS_RX_FOUND props=\(c.properties.rawValue)") }
      if c.uuid == UART_TX_UUID { txChar = c; emitLine("IOS_TX_FOUND props=\(c.properties.rawValue)") }
    }

    if let tx = txChar {
      peripheral.setNotifyValue(true, for: tx)
      emitLine("IOS_SET_NOTIFY true")
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
    emitLine("IOS_NOTIFY_STATE uuid=\(characteristic.uuid.uuidString) isNotifying=\(characteristic.isNotifying) err=\(String(describing: error))")

    if characteristic.uuid == UART_TX_UUID, characteristic.isNotifying, rxChar != nil {
      emitState("READY", deviceId: peripheral.identifier.uuidString)
      if let cr = connectResult {
        cr(nil)
        connectResult = nil
      }
    }
  }

  public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
    if let e = error {
      emitLine("IOS_NOTIFY_ERR \(e.localizedDescription)")
      return
    }
    guard characteristic.uuid == UART_TX_UUID, let data = characteristic.value else { return }

    emitLine("IOS_RX_NOTIFY_FROM \(characteristic.uuid.uuidString) bytes=\(data.count)")
    rxBytesBuffer.append(data)

    while let lfRange = rxBytesBuffer.firstRange(of: Data([0x0A])) {
      var lineData = rxBytesBuffer.subdata(in: 0..<lfRange.lowerBound)
      rxBytesBuffer.removeSubrange(0..<lfRange.upperBound)

      if lineData.last == 0x0D { lineData.removeLast() }

      let line: String
      if let s = String(data: lineData, encoding: .utf8) {
        line = s.trimmingCharacters(in: .whitespacesAndNewlines)
      } else {
        line = lineData.map { String(format: "%02X", $0) }.joined()
      }

      guard !line.isEmpty else { continue }

      if line.count == 64 && line.range(of: "^[0-9A-Fa-f]{64}$", options: .regularExpression) != nil {
        lastChallengeFromWire = line.uppercased()
        emitLine("IOS_CHALL_WIRE \(lastChallengeFromWire!)")
      }

      onIncomingLine(line)
    }
  }

  private func onIncomingLine(_ line: String) {
    emitLine(line)

    if let pr = pending, !pr.completed {
      pr.collected.append(line)
      if line == "OK" {
        pr.completed = true
        pr.timeoutWork?.cancel()
        pending = nil
        pr.result(pr.collected)
      }
    }
  }

  private func startBurst(chunks: [Data], writeType: CBCharacteristicWriteType, delayMs: Int) {
    burstToken &+= 1
    let myToken = burstToken

    pendingChunks = chunks
    pendingWriteType = writeType
    pendingDelayMs = delayMs
    sending = true
    awaitingDidWrite = false
    writeTargetChar = rxChar

    guard writeTargetChar != nil else {
      emitLine("IOS_START_BURST_ABORT rxChar=nil")
      sending = false
      return
    }

    let targetUuidStr = writeTargetChar?.uuid.uuidString ?? "nil"
    emitLine("IOS_WRITE_TARGET uuid=\(targetUuidStr)")

    let wtStr = (writeType == .withoutResponse) ? "WNR" : "WR"
    emitLine("IOS_START_BURST token=\(myToken) chunks=\(chunks.count) writeType=\(wtStr) delayMs=\(delayMs)")

    DispatchQueue.main.async { [weak self] in
      self?.sendNextChunk(token: myToken)
    }
  }

  private func instanceStopScan() {
    if central != nil {
      if central.isScanning {
        central.stopScan()
        emitLine("IOS_STOP_SCAN stopped")
      } else {
        emitLine("IOS_STOP_SCAN not_scanning")
      }
    } else {
      emitLine("IOS_STOP_SCAN no_central")
    }
  }

  // Detailed discovery logging and minimal selection logic
  public func centralManager(_ central: CBCentralManager,
                             didDiscover peripheral: CBPeripheral,
                             advertisementData: [String : Any],
                             rssi RSSI: NSNumber) {
    let advKeys = Array(advertisementData.keys)
    let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
    let name = peripheral.name ?? advName

    emitLine("IOS_DID_DISCOVER name=\(name) id=\(peripheral.identifier.uuidString) rssi=\(RSSI) advKeys=\(advKeys)")

    if let wanted = connectRequestedId, !wanted.isEmpty {
      if peripheral.identifier.uuidString.lowercased() == wanted.lowercased() {
        emitLine("IOS_DID_DISCOVER_SELECTED_BY_ID id=\(peripheral.identifier.uuidString) name=\(name) rssi=\(RSSI)")
        central.stopScan()
        startConnect(to: peripheral)
        return
      } else {
        emitLine("IOS_DID_DISCOVER_IGNORED_BY_ID id=\(peripheral.identifier.uuidString) wanted=\(wanted)")
        return
      }
    }

    let combined = (name + peripheral.identifier.uuidString).lowercased()
    if combined.contains("curebase") {
      emitLine("IOS_DID_DISCOVER_SELECTED id=\(peripheral.identifier.uuidString) name=\(name) rssi=\(RSSI)")
      central.stopScan()
      startConnect(to: peripheral)
    } else {
      emitLine("IOS_DID_DISCOVER_IGNORED id=\(peripheral.identifier.uuidString) name=\(name) rssi=\(RSSI)")
    }
  }
}

