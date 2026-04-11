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

  // Response burst tracking
  private var isResponseBurst: Bool = false
  /// Set for commands that must use the ungated timer-driven WNR path (like response=)
  /// but do NOT trigger the synthetic-OK fallback timer.
  /// Currently used for: progClear, getHardware, getBuild (unlock verification / post-unlock info)
  private var isUngatedWnrBurst: Bool = false
  private var burstChunkIndex: Int = 0
  private var burstTotalChunks: Int = 0
  private var burstStartTimeMs: UInt64 = 0
  /// Set to true once ALL chunks of a response= burst have been physically written.
  /// Used by completePendingOnDisconnect to treat a silent disconnect as a successful unlock.
  private var responseBurstFullySent: Bool = false

  private func currentTimeMs() -> UInt64 {
    return UInt64(DispatchTime.now().uptimeNanoseconds / 1_000_000)
  }

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
      guard let args = call.arguments as? [String: Any],
            let challengeHex = args["challengeHex"] as? String else {
        result(FlutterError(code: "ARG", message: "Missing challengeHex", details: nil))
        return
      }

      // Always delegate to CureCryptoIos for signing so the signing path and
      // its debug logs are consistently executed. Removed temporary hardcoded
      // parity override that returned signatures early and bypassed logging.
      do {
        let sigHex = try CureCryptoIos.buildUnlockResponse(challengeHex: challengeHex)
        emitLine("IOS_PLUGIN_SIG_RETURN challenge=\(challengeHex) sig=\(sigHex) len=\(sigHex.count)")
        result(sigHex)
      } catch {
        emitLine("IOS_PLUGIN_SIG_ERROR challenge=\(challengeHex) error=\(error)")
        result(FlutterError(code: "CRYPTO", message: "buildUnlockResponse failed", details: "\(error)"))
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
    responseBurstFullySent = false  // reset for new command

    let tw = DispatchWorkItem { [weak self] in
      guard let self = self else { return }
      guard let cur = self.pending, cur === pr, !cur.completed else { return }
      cur.completed = true
      self.pending = nil
      cur.result(cur.collected)
    }
    pr.timeoutWork = tw
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(timeoutMs)/1000.0, execute: tw)

    // Single-line protocol: always send "response=<sig>\r\n" as one logical line (Android parity)
    enqueueWrite(line: line)
  }

  /// Called after a response= burst is fully sent.
  /// If the firmware does not reply (it disconnects silently after a valid unlock),
  /// we complete the pending request optimistically with ["OK"] after `delayMs`.
  /// If the device sends a real OK before the timer fires, `onIncomingLine` already
  /// completed the pending and this no-ops.
  private func completePendingWithOkIfSilent(delayMs: Int) {
    guard let pr = pending, !pr.completed else { return }
    emitLine("IOS_RESPONSE_PENDING_OK_TIMER scheduled delayMs=\(delayMs)")
    let capturedPr = pr
    DispatchQueue.main.asyncAfter(deadline: .now() + Double(delayMs) / 1000.0) { [weak self] in
      guard let self = self else { return }
      guard capturedPr === self.pending, !capturedPr.completed else {
        self.emitLine("IOS_RESPONSE_PENDING_OK_TIMER noop (already completed)")
        return
      }
      self.emitLine("IOS_RESPONSE_PENDING_OK_TIMER fired — completing with synthetic OK (device silent after unlock)")
      capturedPr.timeoutWork?.cancel()
      capturedPr.completed = true
      self.pending = nil
      // Use SYNTHETIC_OK so Dart can distinguish from a real device OK
      capturedPr.result(["SYNTHETIC_OK"])
    }
  }

  private func completePendingOnDisconnect() {
    if let pr = pending, !pr.completed {
      pr.timeoutWork?.cancel()

      // If we fully sent a response= burst and the device disconnects silently,
      // this is the firmware's way of signalling a successful unlock.
      // Return ["OK"] instead of an empty list so the Dart layer recognises success.
      if responseBurstFullySent {
        emitLine("IOS_DISCONNECT_AFTER_RESPONSE_BURST — treating as OK (silent unlock disconnect)")
        responseBurstFullySent = false
        pr.completed = true
        pending = nil
        // Use SYNTHETIC_OK so Dart can distinguish from a real device OK
        pr.result(["SYNTHETIC_OK"])
        return
      }

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

    // iOS-STABILISATION (2026-04-02):
    // After unlock the firmware triggers a BLE connection-parameter update.
    // Sending getHardware / getBuild as ATT Write Request (.withResponse) causes
    // an ACK round-trip that races with the parameter update and often leads to
    // a disconnect on iOS. Force .withoutResponse (ATT Write Command) for these
    // two commands — same as Android — to avoid the race condition.
    //
    // progClear is the unlock verification command. It must also use .withoutResponse
    // AND the ungated timer-driven WNR path (no canSendWriteWithoutResponse gate),
    // because the peripheral does not advertise WNR in its characteristic properties.
    let isInfoCommand = (line == "getHardware" || line == "getBuild")
    let isProgClear   = (line == "progClear")

    // Determine write type:
    // ANDROID PARITY FIX (2026-03-30):
    // Android sends response= with WRITE_TYPE_NO_RESPONSE (ATT Write Command, no ACK expected).
    // The firmware expects ATT Write Commands and does NOT send an ATT Write Response.
    // When iOS uses .withResponse (ATT Write Request), the firmware never ACKs it → disconnect.
    //
    // CoreBluetooth DOES send .withoutResponse writes even if WNR is not in the property bits.
    // The property check in the iOS stack does not block the actual BLE packet — it only blocks
    // if you use the canSendWriteWithoutResponse API. Direct writeValue(...type:.withoutResponse)
    // always sends the ATT Write Command regardless of the advertised properties.
    //
    // Therefore: for response=, ALWAYS use .withoutResponse (Android parity).
    // For getHardware/getBuild: FORCE .withoutResponse (iOS post-unlock stabilisation).
    // For all other commands: use .withResponse if WNR not advertised (safe default).
    let candidateWriteType: CBCharacteristicWriteType
    if isResponse {
      // FORCE WNR for response= — matches Android WRITE_TYPE_NO_RESPONSE behavior exactly.
      candidateWriteType = .withoutResponse
      emitLine("IOS_RESPONSE_MODE WNR_ANDROID_PARITY (hasWNR=\(hasWNR) hasWR=\(hasWR) — forcing WNR to match Android ATT Write Command)")
    } else if isProgClear {
      // FORCE WNR for progClear — unlock verification command, uses ungated WNR path (Android parity).
      candidateWriteType = .withoutResponse
      emitLine("IOS_PROGCLEAR_WNR_ANDROID_PARITY (hasWNR=\(hasWNR) hasWR=\(hasWR) — forcing ungated WNR for progClear)")
      emitLine("IOS_FORCE_WNR_FOR_CMD progClear")
    } else if isInfoCommand {
      // FORCE WNR for getHardware/getBuild — post-unlock iOS stabilisation.
      candidateWriteType = .withoutResponse
      emitLine("IOS_FORCE_WNR_FOR_CMD \(line)")
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

    var chunks: [Data] = []
    let delayMs: Int

    if isResponse {
      // ANDROID PARITY: split into 20-byte chunks, 45ms inter-chunk delay.
      // Android: 7 chunks × 20 bytes (last chunk 19 bytes + CRLF), delayMs=45.
      // No canSendWriteWithoutResponse gating — pure timer-based pacing like Android.
      let chunkSize = 20
      var offset = 0
      while offset < payloadData.count {
        let end = min(offset + chunkSize, payloadData.count)
        chunks.append(payloadData.subdata(in: offset..<end))
        offset = end
      }
      delayMs = 45
      emitLine("IOS_RESPONSE_WRITE_META totalBytes=\(payloadData.count) totalChunks=\(chunks.count) writeType=WNR chunkSize=\(chunkSize) delayMs=\(delayMs) mode=WNR_ANDROID_PARITY")
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
      delayMs = 10
    }
    pendingDelayMs = delayMs

    emitLine("IOS_WRITE_SPLIT chunks=\(chunks.count) delayMs=\(delayMs)")

    writeTargetChar = rx
    emitLine("IOS_WRITE_TARGET uuid=\(writeTargetChar?.uuid.uuidString ?? "nil")")

    peripheral?.delegate = self
    emitLine("IOS_SET_DELEGATE_BEFORE_BURST delegate=\(String(describing: peripheral?.delegate)) self=\(type(of: self))")

    // Start burst immediately (didWrite callbacks handle inter-chunk pacing)
    // isInfoCommand (getHardware/getBuild) must also use the ungated WNR path so they
    // are not blocked by canSendWriteWithoutResponse after a post-unlock connection
    // parameter update — same reason as progClear.
    startBurst(chunks: chunks, writeType: candidateWriteType, delayMs: delayMs, isResponseBurst: isResponse, isUngatedWnrBurst: isProgClear || isInfoCommand)
  }

  // MARK: - Burst sender

  private func sendNextChunk(token: Int) {
    let wtLabel = (pendingWriteType == .withResponse) ? "WR" : "WNR"
    let ts = currentTimeMs() - burstStartTimeMs
    emitLine("IOS_BUILD_MARKER_2026_03_29 sendNextChunk entered writeType=\(wtLabel) chunkIdx=\(burstChunkIndex) ts=\(ts)ms")

    guard sending else { return }
    guard token == burstToken else { return }
    guard let p = peripheral, let target = writeTargetChar ?? rxChar else { return }

    if pendingChunks.isEmpty {
      sending = false
      let finishTs = currentTimeMs() - burstStartTimeMs
      emitLine("IOS_WRITE_DONE ts=\(finishTs)ms")
      if isResponseBurst {
        emitLine("IOS_RESPONSE_BURST_FINISHED awaiting_device_reply=true totalChunks=\(burstTotalChunks) elapsed=\(finishTs)ms")
        isResponseBurst = false
        responseBurstFullySent = true
        // Firmware may disconnect silently after a valid unlock (no explicit OK).
        // Optimistically complete pending with OK after 2s if the device hasn't replied yet.
        completePendingWithOkIfSilent(delayMs: 2000)
      } else if isUngatedWnrBurst {
        // ungated WNR burst (e.g. progClear) finished — no synthetic-OK timer, device reply expected normally
        isUngatedWnrBurst = false
        emitLine("IOS_UNGATED_WNR_BURST_DONE totalChunks=\(burstTotalChunks) elapsed=\(finishTs)ms awaiting_device_reply=true")
      }
      return
    }

    if pendingWriteType == .withoutResponse {
      if isResponseBurst || isUngatedWnrBurst {
        // Ungated WNR path (response=, progClear, getHardware, getBuild):
        //
        // Android sends these commands using WRITE_TYPE_NO_RESPONSE (ATT Write Command)
        // with a fixed inter-chunk delay. It does NOT gate on canSendWriteWithoutResponse.
        //
        // Fix (2026-03-30/04-02): Do NOT check canSendWriteWithoutResponse for these bursts.
        // getHardware/getBuild are also added here (2026-04-02) because after a post-unlock
        // connection parameter update, canSendWriteWithoutResponse stays false and blocks them.
        // Write each chunk directly (CoreBluetooth sends ATT Write Command regardless of
        // advertised properties), paced by the timer — exactly matching Android.
        guard !pendingChunks.isEmpty else {
          let ts0 = currentTimeMs() - burstStartTimeMs
          emitLine("IOS_RESPONSE_WNR_ALREADY_DONE ts=\(ts0)ms (concurrent guard)")
          return
        }

        let chunk = pendingChunks.removeFirst()
        let idx = burstChunkIndex
        burstChunkIndex += 1
        let sendTs = currentTimeMs() - burstStartTimeMs
        let totalForHasCrlf = burstTotalChunks
        let hasCRLF = (pendingChunks.isEmpty) // last chunk contains \r\n
        if isResponseBurst {
          emitLine("IOS_RESPONSE_CHUNK idx=\(idx + 1)/\(totalForHasCrlf) len=\(chunk.count) hasCRLF=\(hasCRLF) tsMs=\(sendTs)")
        } else {
          emitLine("IOS_UNGATED_WNR_CHUNK idx=\(idx + 1)/\(totalForHasCrlf) len=\(chunk.count) hasCRLF=\(hasCRLF) tsMs=\(sendTs)")
        }
        emitLine("IOS_WRITE_CHUNK len=\(chunk.count) type=WNR remaining=\(pendingChunks.count)")
        emitLine("IOS_WRITE_TO uuid=\(target.uuid.uuidString) expected=\(UART_RX_UUID.uuidString)")
        p.delegate = self
        p.writeValue(chunk, for: target, type: .withoutResponse)
        if pendingChunks.isEmpty {
          sending = false
          let finishTs = currentTimeMs() - burstStartTimeMs
          if isResponseBurst {
            emitLine("IOS_RESPONSE_DONE totalChunks=\(burstTotalChunks) elapsedMs=\(finishTs)")
            emitLine("IOS_WRITE_DONE ts=\(finishTs)ms")
            emitLine("IOS_RESPONSE_BURST_FINISHED awaiting_device_reply=true totalChunks=\(burstTotalChunks) elapsed=\(finishTs)ms")
            isResponseBurst = false
            responseBurstFullySent = true
            // Firmware may disconnect silently after a valid unlock (no explicit OK).
            // Optimistically complete pending with OK after 2s if the device hasn't replied yet.
            completePendingWithOkIfSilent(delayMs: 2000)
          } else {
            emitLine("IOS_WRITE_DONE ts=\(finishTs)ms")
            emitLine("IOS_UNGATED_WNR_BURST_DONE totalChunks=\(burstTotalChunks) elapsed=\(finishTs)ms awaiting_device_reply=true")
            isUngatedWnrBurst = false
          }
          return
        }
        // Schedule next chunk after delay (no canSendWriteWithoutResponse gating — Android parity).
        let myToken = token
        let chunkDelayMs = pendingDelayMs
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(chunkDelayMs) / 1000.0) { [weak self] in
          guard let self = self else { return }
          guard self.sending, self.burstToken == myToken else { return }
          self.sendNextChunk(token: myToken)
        }
        return
      }

      // Normal WNR path (non-response): use canSendWriteWithoutResponse
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
      // If still awaiting didWrite for previous chunk, do NOT send next chunk yet
      if awaitingDidWrite {
        emitLine("IOS_WR_SKIP_AWAITING_DIDWRITE chunkIdx=\(burstChunkIndex) remaining=\(pendingChunks.count)")
        return
      }

      let chunk = pendingChunks.removeFirst()
      let idx = burstChunkIndex
      burstChunkIndex += 1
      awaitingDidWrite = true
      let sendTs = currentTimeMs() - burstStartTimeMs
      emitLine("IOS_WR_CHUNK_SENT_AT index=\(idx) remaining=\(pendingChunks.count) len=\(chunk.count) ts=\(sendTs)ms")
      if isResponseBurst {
        let hasCRLF = pendingChunks.isEmpty
        emitLine("IOS_RESPONSE_CHUNK idx=\(idx + 1)/\(burstTotalChunks) len=\(chunk.count) hasCRLF=\(hasCRLF) tsMs=\(sendTs)")
      }
      emitLine("IOS_WRITE_CHUNK len=\(chunk.count) type=WR remaining=\(pendingChunks.count)")

      // Ensure delegate is set and log BEFORE the actual writeValue call
      p.delegate = self
      let targetUuid = target.uuid.uuidString
      let rxUuid = rxChar?.uuid.uuidString ?? "nil"
      let targetPtr = Unmanaged.passUnretained(target).toOpaque()
      let rxPtr = rxChar.map { Unmanaged.passUnretained($0).toOpaque() }
      emitLine("IOS_WRITE_CALL uuid=\(targetUuid) type=WR token=\(token) chunkIdx=\(idx) len=\(chunk.count) targetPtr=\(targetPtr) rxPtr=\(String(describing: rxPtr)) sameObj=\(target === rxChar)")
      emitLine("IOS_WRITE_TO uuid=\(targetUuid) expected=\(UART_RX_UUID.uuidString)")
      p.writeValue(chunk, for: target, type: .withResponse)

      // Watchdog fallback: if no didWrite arrives within timeout, log clearly and advance
      let myToken = token
      // For response burst: single WR write, firmware needs time to verify signature.
      // Use generous watchdog (5000ms) — if didWrite never arrives, advance anyway.
      // For other WR commands: use max(200, pendingDelayMs).
      let watchdogMs = isResponseBurst ? 5000 : max(200, pendingDelayMs)
      let delaySec = Double(watchdogMs) / 1000.0
      DispatchQueue.main.asyncAfter(deadline: .now() + delaySec) { [weak self] in
        guard let self = self else { return }
        guard self.sending, self.burstToken == myToken else { return }
        guard self.awaitingDidWrite else { return }

        let wdTs = self.currentTimeMs() - self.burstStartTimeMs
        self.emitLine("IOS_WR_FALLBACK_NO_DIDWRITE index=\(idx) remaining=\(self.pendingChunks.count) ts=\(wdTs)ms delaySec=\(delaySec)")
        self.awaitingDidWrite = false
        self.sendNextChunk(token: myToken)
      }
      return
    }
  }

  public func peripheral(_ peripheral: CBPeripheral,
                         didWriteValueFor characteristic: CBCharacteristic,
                         error: Error?) {
    let ts = currentTimeMs() - burstStartTimeMs
    let idx = burstChunkIndex - 1  // last sent index
    let charUuid = characteristic.uuid.uuidString
    let rxUuid = rxChar?.uuid.uuidString ?? "nil"
    let targetUuid = writeTargetChar?.uuid.uuidString ?? "nil"
    let uuidMatchRx = (characteristic.uuid == rxChar?.uuid)
    let uuidMatchTarget = (characteristic.uuid == writeTargetChar?.uuid)
    let objMatchRx = (characteristic === rxChar)
    let objMatchTarget = (characteristic === writeTargetChar)
    let charPtr = Unmanaged.passUnretained(characteristic).toOpaque()
    let rxPtr = rxChar.map { Unmanaged.passUnretained($0).toOpaque() }
    let targetPtr = writeTargetChar.map { Unmanaged.passUnretained($0).toOpaque() }
    let peripheralId = peripheral.identifier.uuidString

    emitLine("IOS_DID_WRITE uuid=\(charUuid) err=\(error == nil ? "nil" : error!.localizedDescription) status=\(error == nil ? "ok" : "fail")")
    emitLine("IOS_DID_WRITE_MATCH_RX=\(uuidMatchRx) objMatchRx=\(objMatchRx) rxUuid=\(rxUuid)")
    emitLine("IOS_DID_WRITE_MATCH_TARGET=\(uuidMatchTarget) objMatchTarget=\(objMatchTarget) targetUuid=\(targetUuid)")
    emitLine("IOS_DID_WRITE_SENDING=\(sending) awaitingDidWrite=\(awaitingDidWrite)")
    emitLine("IOS_DID_WRITE_TOKEN=\(burstToken) chunkIdx=\(idx) remaining=\(pendingChunks.count) ts=\(ts)ms")
    emitLine("IOS_DID_WRITE_PTRS charPtr=\(charPtr) rxPtr=\(String(describing: rxPtr)) targetPtr=\(String(describing: targetPtr)) peripheral=\(peripheralId)")

    if let e = error {
      emitError("write error: \(e.localizedDescription)")
      awaitingDidWrite = false
      return
    }

    // Accept callback if UUID matches either rxChar or writeTargetChar
    guard uuidMatchRx || uuidMatchTarget else {
      emitLine("IOS_DID_WRITE_IGNORED_UUID_MISMATCH char=\(charUuid) rx=\(rxUuid) target=\(targetUuid)")
      return
    }

    guard sending else {
      emitLine("IOS_DID_WRITE_IGNORED_NOT_SENDING")
      return
    }

    awaitingDidWrite = false
    let token = burstToken
    DispatchQueue.main.async { [weak self] in
      self?.sendNextChunk(token: token)
    }
  }

  /// Called by iOS BLE stack when peripheral is ready to accept another WNR write.
  public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    let ts = currentTimeMs() - burstStartTimeMs
    emitLine("IOS_PERIPHERAL_IS_READY_WNR ts=\(ts)ms sending=\(sending) isResponseBurst=\(isResponseBurst) remaining=\(pendingChunks.count)")
    // For response bursts: this is the primary flow-control signal.
    // When canSendWriteWithoutResponse becomes true, peripheralIsReady fires and
    // we continue sending the next chunk (same for normal WNR bursts).
    guard sending else { return }
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

  private func startBurst(chunks: [Data], writeType: CBCharacteristicWriteType, delayMs: Int, isResponseBurst: Bool = false, isUngatedWnrBurst: Bool = false) {
    burstToken &+= 1
    let myToken = burstToken

    pendingChunks = chunks
    pendingWriteType = writeType
    pendingDelayMs = delayMs
    sending = true
    awaitingDidWrite = false
    writeTargetChar = rxChar

    // isResponseBurst is passed in from enqueueWrite based on line prefix "response="
    self.isResponseBurst = isResponseBurst
    // isUngatedWnrBurst: uses same ungated timer-driven WNR path as response=, but no synthetic-OK timer
    self.isUngatedWnrBurst = isUngatedWnrBurst
    burstChunkIndex = 0
    burstTotalChunks = chunks.count
    burstStartTimeMs = currentTimeMs()

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

