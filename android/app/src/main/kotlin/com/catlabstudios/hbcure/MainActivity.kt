package com.catlabstudios.hbcure

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.content.Intent
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

class MainActivity : FlutterActivity() {

    companion object {
        private const val TAG = "CureBleNative"
        private const val METHOD_CHANNEL = "cure_ble_native/methods"
        private const val EVENT_CHANNEL = "cure_ble_native/notify"

        private val UART_SERVICE_UUID: UUID =
            UUID.fromString("6e400001-b5a3-f393-e0a9-e50e24dcca9e")
        // Device RX (Central writes here)
        private val UART_RX_UUID: UUID =
            UUID.fromString("6e400002-b5a3-f393-e0a9-e50e24dcca9e")
        // Device TX (Central receives notifications here)
        private val UART_TX_UUID: UUID =
            UUID.fromString("6e400003-b5a3-f393-e0a9-e50e24dcca9e")

        private val CCC_DESCRIPTOR_UUID: UUID =
            UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")

        // TEMP DEBUG flag: ensure we log the Android test signature only once.
        // TEMP DEBUG – REMOVE AFTER SIGNATURE COMPARISON
        private var ANDROID_TEST_SIG_LOGGED: Boolean = false
        private var ANDROID_IOS_CHALL_SIG_LOGGED: Boolean = false
        // One-time log for the requested test challenge signature
        private var ANDROID_PRODUCED_SIG_LOGGED: Boolean = false
        // One-time log for the specific comparison challenge
        private var ANDROID_SPECIFIC_SIG_LOGGED: Boolean = false
        // One-time log for the newly requested challenge (2650...)
        private var ANDROID_CHALL_2650_LOGGED: Boolean = false
        // One-time log for the exact runtime challenge requested for parity test
        private var ANDROID_RUNTIME_SIG_LOGGED: Boolean = false
        // One-time log for challenge 014781... (iOS parity check)
        private var ANDROID_SIG_014781_LOGGED: Boolean = false
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var eventSink: EventChannel.EventSink? = null

    private val bleManager: CureBleManager by lazy {
        CureBleManager(applicationContext) { event: Map<String, Any> ->
            runOnUiThread {
                eventSink?.success(event)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        )

        eventChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        )

        setupMethodChannel()
        setupEventChannel()
    }

    private fun setupMethodChannel() {
        methodChannel.setMethodCallHandler { call: MethodCall, result: MethodChannel.Result ->
            when (call.method) {
                "connect" -> {
                    val deviceId = extractDeviceId(call.arguments)
                    Log.d(TAG, "Method connect($deviceId)")
                    bleManager.connect(deviceId, result)
                }

                "disconnect" -> {
                    Log.d(TAG, "Method disconnect()")
                    bleManager.disconnect()
                    result.success(null)
                }

                "writeLine" -> {
                    val line = extractLine(call.arguments)
                    Log.d(TAG, "Method writeLine($line)")
                    bleManager.writeLine(line, result)
                }

                "sendCommandAndWaitLines" -> {
                    val args = call.arguments
                    val (line, timeoutMs) = extractSendCommandArgs(args)
                    Log.d(TAG, "Method sendCommandAndWaitLines(line=$line, timeoutMs=$timeoutMs)")
                    bleManager.sendCommandAndWaitLines(line, timeoutMs, result)
                }

                "buildUnlockResponse" -> {
                    val challengeHex = when (call.arguments) {
                        is String -> call.arguments as String
                        is Map<*, *> -> (call.arguments as Map<*, *>)["challengeHex"] as? String ?: ""
                        else -> ""
                    }
                    Log.d(TAG, "Method buildUnlockResponse(challengeHex=${challengeHex.take(16)}...)")
                    if (challengeHex.isEmpty()) {
                        result.error("ARG_ERROR", "challengeHex missing", null)
                    } else {
                        // TEMP DEBUG – REMOVE AFTER IOS/ANDROID CHALLENGE SIGNATURE COMPARISON
                        // Log the signature for a fixed challenge exactly once so we can compare Android vs iOS output.
                        try {
                            if (!ANDROID_TEST_SIG_LOGGED) {
                                CureCrypto.testSignFixed()
                                ANDROID_TEST_SIG_LOGGED = true
                            }
                            // One-time log for the runtime challenge signature (requested by QA)
                            if (!ANDROID_RUNTIME_SIG_LOGGED) {
                                val runtimeChallenge = "6D7A385616CA4511DEFBDB3AB9AD0AC3C882259EF2BB4D16CFCC93BA0798D0FE"
                                try {
                                    val sigRuntime = CureCrypto.buildUnlockResponse(runtimeChallenge)
                                    Log.d("CureCrypto", "ANDROID_SIG_RUNTIME=$sigRuntime")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "ANDROID_SIG_RUNTIME failed", e)
                                }
                                ANDROID_RUNTIME_SIG_LOGGED = true
                            }
                            if (!ANDROID_PRODUCED_SIG_LOGGED) {
                                val testChallenge = "0606F9AB14A8D823D8380C015B6D73BD3C75609BEC1D4421345489146C655072"
                                try {
                                    val sig = CureCrypto.buildUnlockResponse(testChallenge)
                                    Log.d("CureCrypto", "PRODUCED_ANDROID_SIG=$sig")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "PRODUCED_ANDROID_SIG failed", e)
                                }
                                ANDROID_PRODUCED_SIG_LOGGED = true
                            }
                            if (!ANDROID_IOS_CHALL_SIG_LOGGED) {
                                val testChallenge = "317A4D9A435A7F4FCD7BE869E74933637576A7B29F6F30E0FD855394B86B532D"
                                try {
                                    val testSig = CureCrypto.buildUnlockResponse(testChallenge)
                                    Log.d("CureCrypto", "ANDROID_IOS_CHALL_SIG=$testSig")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "ANDROID_IOS_CHALL_SIG failed", e)
                                }
                                ANDROID_IOS_CHALL_SIG_LOGGED = true
                            }
                            // Specific requested challenge signature log (one-time)
                            if (!ANDROID_SPECIFIC_SIG_LOGGED) {
                                val specific = "202ED6CB1D7161FEA22CDD84A162FE7C34640BDB4AE10822816FE4762F9D6086"
                                try {
                                    val specificSig = CureCrypto.buildUnlockResponse(specific)
                                    Log.d("CureCrypto", "ANDROID_SIG=$specificSig")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "ANDROID_SIG failed", e)
                                }
                                ANDROID_SPECIFIC_SIG_LOGGED = true
                            }
                            // One-time log for the requested challenge 2650F8...
                            if (!ANDROID_CHALL_2650_LOGGED) {
                                val specific2650 = "2650F820DB423D9C9EC70872B16306F2C2C74F31F4794FBE0C879BC1C950961F"
                                try {
                                    val sig2650 = CureCrypto.buildUnlockResponse(specific2650)
                                    Log.d("CureCrypto", "ANDROID_SIG_2650=$sig2650")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "ANDROID_SIG_2650 failed", e)
                                }
                                ANDROID_CHALL_2650_LOGGED = true
                            }
                            // One-time log for the newly requested runtime challenge (from QA)
                            if (!ANDROID_RUNTIME_SIG_LOGGED) {
                                val requested = "592F63ABB40870DB06733F7683BCA1B564578F2AD39BB9D59B20A27D63972EE7"
                                try {
                                    val sigRuntime2 = CureCrypto.buildUnlockResponse(requested)
                                    Log.d("CureCrypto", "ANDROID_SIG_RUNTIME=$sigRuntime2")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "ANDROID_SIG_RUNTIME failed", e)
                                }
                                ANDROID_RUNTIME_SIG_LOGGED = true
                            }
                            // One-time log for challenge 014781... (iOS parity check)
                            if (!ANDROID_SIG_014781_LOGGED) {
                                val chall014781 = "014781D97C2D01F522E6E4CD4574622C8641F7D27F7333EAE4F768B475BA2977"
                                try {
                                    val sig014781 = CureCrypto.buildUnlockResponse(chall014781)
                                    Log.d("CureCrypto", "ANDROID_SIG_014781=$sig014781")
                                } catch (e: Exception) {
                                    Log.w("CureCrypto", "ANDROID_SIG_014781 failed", e)
                                }
                                ANDROID_SIG_014781_LOGGED = true
                            }
                        } catch (e: Exception) {
                            Log.w(TAG, "TEMP DEBUG signature log failed", e)
                        }

                        try {
                            val sigHex = CureCrypto.buildUnlockResponse(challengeHex)
                            result.success(sigHex)
                        } catch (e: Exception) {
                            Log.e(TAG, "buildUnlockResponse failed", e)
                            result.error("SIGN_FAILED", e.message ?: "unknown", null)
                        }
                    }
                }

                "verifyDeviceSignature" -> {
                    val challengeHex = call.argument<String>("challengeHex") ?: ""
                    val sigHex = call.argument<String>("sigHex") ?: ""
                    Log.d(
                        TAG,
                        "Method verifyDeviceSignature(challengeHex=${challengeHex.take(16)}..., sigHex=${sigHex.take(16)}...)"
                    )

                    if (challengeHex.isEmpty() || sigHex.isEmpty()) {
                        result.error("ARG_ERROR", "challengeHex or sigHex missing", null)
                    } else {
                        try {
                            val isValid = CureCrypto.verifyDeviceSignature(challengeHex, sigHex)
                            result.success(isValid)
                        } catch (e: Exception) {
                            Log.e(TAG, "verifyDeviceSignature failed", e)
                            result.error("VERIFY_FAILED", e.message ?: "unknown", null)
                        }
                    }
                }

                "isLocationServiceEnabled" -> {
                    val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
                    val enabled = lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                            lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
                    result.success(enabled)
                }

                "openLocationSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message ?: "unknown", null)
                    }
                }

                "openAppSettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                        intent.data = android.net.Uri.fromParts("package", packageName, null)
                        intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("SETTINGS_ERROR", e.message ?: "unknown", null)
                    }
                }

                "requestBlePermissions" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        requestPermissions(arrayOf(
                            android.Manifest.permission.BLUETOOTH_SCAN,
                            android.Manifest.permission.BLUETOOTH_CONNECT,
                        ), 1001)
                    } else {
                        requestPermissions(arrayOf(
                            android.Manifest.permission.ACCESS_FINE_LOCATION,
                        ), 1001)
                    }
                    result.success(null)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupEventChannel() {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                Log.d(TAG, "EventChannel onListen")
                eventSink = sink
            }

            override fun onCancel(arguments: Any?) {
                Log.d(TAG, "EventChannel onCancel")
                eventSink = null
            }
        })
    }

    // ---- Argument-Helper ----

    private fun extractDeviceId(arguments: Any?): String {
        return when (arguments) {
            is String -> arguments
            is Map<*, *> -> arguments["deviceId"] as? String ?: ""
            else -> ""
        }
    }

    private fun extractLine(arguments: Any?): String {
        return when (arguments) {
            is String -> arguments
            is Map<*, *> -> arguments["line"] as? String ?: ""
            else -> ""
        }
    }

    private fun extractSendCommandArgs(arguments: Any?): Pair<String, Long> {
        var line = ""
        var timeoutMs = 5000L

        when (arguments) {
            is String -> {
                line = arguments
            }

            is Map<*, *> -> {
                line = arguments["line"] as? String ?: ""
                timeoutMs = (arguments["timeoutMs"] as? Number)?.toLong() ?: 5000L
            }
        }

        return Pair(line, timeoutMs)
    }

    // ------------------------------------------------------------------------
    //  Nativer BLE-Manager (GATT-Client für CureBase)
    // ------------------------------------------------------------------------

    private class CureBleManager(
        private val context: Context,
        private val eventCallback: (Map<String, Any>) -> Unit
    ) {

        private val TAG = "CureBleManager"

        private val bluetoothManager: BluetoothManager =
            context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        private val bluetoothAdapter: BluetoothAdapter? = bluetoothManager.adapter

        private var bluetoothGatt: BluetoothGatt? = null
        private var rxCharacteristic: BluetoothGattCharacteristic? = null
        private var txCharacteristic: BluetoothGattCharacteristic? = null

        private val handler: Handler = Handler(Looper.getMainLooper())

        // Pending Request für sendCommandAndWaitLines
        private data class PendingRequest(
            val line: String,
            val timeoutMs: Long,
            val result: MethodChannel.Result,
            val collected: MutableList<String> = mutableListOf(),
            var completed: Boolean = false
        )

        private var pendingRequest: PendingRequest? = null

        // Buffer für eingehende UART-Daten → Zeilen aufspalten
        private val incomingBuffer = StringBuilder()

        private var pendingConnectResult: MethodChannel.Result? = null

        // ---- WRITE: Qt-like burst (WriteWithoutResponse) ----
        private val writeHandler = Handler(Looper.getMainLooper())
        private var burstToken: Long = 0L
        private var writeInFlight: Boolean = false
        // Flag: waiting for CCC descriptor write to finish before completing connect
        private var awaitingCccd: Boolean = false
        // Diagnostic: track whether last sent command was response= (for ANDROID_RESPONSE_RESULT logging)
        private var awaitingResponseOk: Boolean = false

        private fun completePendingConnectSuccess() {
            val pending = pendingConnectResult ?: return
            pendingConnectResult = null
            try {
                pending.success(null)
            } catch (e: Exception) {
                Log.w(TAG, "completePendingConnectSuccess: callback threw: $e")
            }
        }

        private fun completePendingConnectError(code: String, message: String) {
            val pending = pendingConnectResult ?: return
            pendingConnectResult = null
            try {
                pending.error(code, message, null)
            } catch (e: Exception) {
                Log.w(TAG, "completePendingConnectError: callback threw: $e")
            }
        }

        fun connect(deviceId: String, result: MethodChannel.Result) {
            if (deviceId.isEmpty()) {
                result.error("ARG_ERROR", "deviceId is empty", null)
                return
            }

            val adapter = bluetoothAdapter
            if (adapter == null || !adapter.isEnabled) {
                result.error("BT_OFF", "Bluetooth is not enabled", null)
                return
            }

            pendingConnectResult?.let { pending ->
                try {
                    pending.error("CANCELLED", "Previous connect cancelled by new connect()", null)
                } catch (_: Exception) {}
            }
            pendingConnectResult = result

            try {
                val device: BluetoothDevice = adapter.getRemoteDevice(deviceId)

                try {
                    bluetoothGatt?.close()
                } catch (_: Exception) {}
                bluetoothGatt = null
                rxCharacteristic = null
                txCharacteristic = null
                pendingRequest = null
                incomingBuffer.clear()

                burstToken = 0L
                writeInFlight = false
                awaitingCccd = false
                writeHandler.removeCallbacksAndMessages(null)

                eventCallback(
                    mapOf(
                        "type" to "state",
                        "state" to "CONNECTING",
                        "deviceId" to deviceId
                    )
                )

                bluetoothGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
                } else {
                    @Suppress("DEPRECATION")
                    device.connectGatt(context, false, gattCallback)
                }
            } catch (e: IllegalArgumentException) {
                Log.e(TAG, "connect: invalid deviceId=$deviceId", e)
                pendingConnectResult = null
                result.error("ARG_ERROR", "Invalid deviceId: $deviceId", null)
            } catch (e: Exception) {
                Log.e(TAG, "connect: unexpected error $e")
                pendingConnectResult = null
                result.error("CONNECT_FAILED", "Unexpected error: ${e.message}", null)
            }
        }

        fun disconnect() {
            pendingRequest?.let { pr ->
                if (!pr.completed) {
                    pr.completed = true
                    try {
                        pr.result.success(ArrayList(pr.collected))
                    } catch (_: Exception) {}
                }
                pendingRequest = null
            }

            burstToken = 0L
            writeInFlight = false
            awaitingCccd = false
            writeHandler.removeCallbacksAndMessages(null)
            incomingBuffer.clear()

            try { bluetoothGatt?.disconnect() } catch (_: Exception) {}
            try { bluetoothGatt?.close() } catch (_: Exception) {}

            bluetoothGatt = null
            rxCharacteristic = null
            txCharacteristic = null

            eventCallback(
                mapOf(
                    "type" to "state",
                    "state" to "DISCONNECTED"
                )
            )
        }

        fun writeLine(line: String, result: MethodChannel.Result) {
            enqueueWrite(line)
            result.success(null)
        }

        fun sendCommandAndWaitLines(line: String, timeoutMs: Long, result: MethodChannel.Result) {
            val gatt = bluetoothGatt
            val rx = rxCharacteristic
            if (gatt == null || rx == null) {
                Log.w(TAG, "sendCommandAndWaitLines: no GATT or RX characteristic")
                result.error("NOT_CONNECTED", "Not connected or UART characteristics not discovered", null)
                return
            }

            val existing = pendingRequest
            if (existing != null && !existing.completed) {
                Log.w(TAG, "sendCommandAndWaitLines: another command is already in progress")
                result.error("BUSY", "Another command is already in progress", null)
                return
            }

            val request = PendingRequest(line = line, timeoutMs = timeoutMs, result = result)
            pendingRequest = request

            Log.d(TAG, "sendCommandAndWaitLines: starting cmd='$line', timeoutMs=$timeoutMs")
            Log.d(TAG, "sendCommandAndWaitLines: FULL LINE before CRLF='$line'")

            handler.postDelayed({
                val pr = pendingRequest
                if (pr != null && pr === request && !pr.completed) {
                    Log.w(TAG, "sendCommandAndWaitLines timeout after ${timeoutMs} ms (cmd='${line}')")
                    pr.completed = true
                    pendingRequest = null
                    try {
                        pr.result.success(ArrayList(pr.collected))
                    } catch (_: Exception) {}
                    incomingBuffer.clear()
                }
            }, timeoutMs)

            enqueueWrite(line)
        }

        private fun enqueueWrite(line: String) {
            val gatt = bluetoothGatt ?: return
            val rx = rxCharacteristic ?: return

            val full = (line + "\r\n").toByteArray(Charsets.UTF_8)

            if (line.startsWith("response=")) {
                val sb = StringBuilder()
                full.forEach { b -> sb.append(String.format("%02X ", b)) }
                Log.d(TAG, "enqueueWrite: response bytes=$sb")
            }

            // Cancel previous burst (if any) and start new one
            burstToken = System.nanoTime()
            val token = burstToken
            writeInFlight = false

            // Force WriteWithoutResponse like Qt
            rx.writeType = WRITE_TYPE_NO_RESPONSE

            // 20 bytes like Qt
            val chunkSize = 20
            val chunks = ArrayList<ByteArray>()
            var offset = 0
            while (offset < full.size) {
                val end = (offset + chunkSize).coerceAtMost(full.size)
                chunks.add(full.copyOfRange(offset, end))
                offset = end
            }

            // ✅ Samsung A03s Fix: pace stronger (especially for response=)
            // Use slightly larger per-chunk delay for longer-sensitive commands
            val perChunkDelayMs = when {
                line.startsWith("response=") -> 45L
                line.startsWith("sign=") -> 60L
                line.startsWith("progAppend=") -> 45L
                else -> 20L
            }

            // ANDROID_RESPONSE diagnostic: log meta for response= commands only
            val isResponseCmd = line.startsWith("response=")
            val writeTypeLabel = if (rx.writeType == WRITE_TYPE_NO_RESPONSE) "WRITE_TYPE_NO_RESPONSE" else "WRITE_TYPE_DEFAULT"
            if (isResponseCmd) {
                Log.d(TAG, "ANDROID_RESPONSE_WRITE_META totalBytes=${full.size} totalChunks=${chunks.size} writeType=$writeTypeLabel chunkSize=$chunkSize delayMs=$perChunkDelayMs")
                val lastChunkHex = chunks.lastOrNull()?.joinToString(" ") { String.format("%02X", it) } ?: ""
                val hasCrlfInLast = full.size >= 2 && full[full.size - 2] == 0x0D.toByte() && full[full.size - 1] == 0x0A.toByte()
                Log.d(TAG, "ANDROID_RESPONSE_CRLF appendedCRLF=$hasCrlfInLast lastChunkHex=$lastChunkHex")
                awaitingResponseOk = true
            }
            val burstStartMs = if (isResponseCmd) System.currentTimeMillis() else 0L

            fun sendChunk(i: Int) {
                if (burstToken != token) return // cancelled
                if (i >= chunks.size) {
                    Log.d(TAG, "enqueueWrite: burst done (chunks=${chunks.size})")
                    if (isResponseCmd) {
                        val elapsed = System.currentTimeMillis() - burstStartMs
                        Log.d(TAG, "ANDROID_RESPONSE_DONE totalChunks=${chunks.size} elapsedMs=$elapsed")
                    }
                    return
                }
                if (writeInFlight) {
                    writeHandler.postDelayed({ sendChunk(i) }, perChunkDelayMs)
                    return
                }

                val chunk = chunks[i]
                rx.value = chunk

                Log.d(TAG, "burst: write chunk ${i + 1}/${chunks.size}, len=${chunk.size}")

                // ANDROID_RESPONSE diagnostic per chunk
                if (isResponseCmd) {
                    val hexStr = chunk.joinToString(" ") { String.format("%02X", it) }
                    val asciiStr = chunk.map { b ->
                        val c = b.toInt() and 0xFF
                        if (c in 32..126) c.toChar() else '.'
                    }.joinToString("")
                    val hasCrlf = chunk.size >= 2 &&
                        chunk[chunk.size - 2] == 0x0D.toByte() &&
                        chunk[chunk.size - 1] == 0x0A.toByte()
                    val tsMs = System.currentTimeMillis() - burstStartMs
                    Log.d(TAG, "ANDROID_RESPONSE_CHUNK idx=${i + 1}/${chunks.size} len=${chunk.size} type=$writeTypeLabel hasCRLF=$hasCrlf tsMs=$tsMs ascii=\"$asciiStr\" hex=$hexStr")
                }

                val ok = gatt.writeCharacteristic(rx)
                if (!ok) {
                    Log.w(TAG, "burst: writeCharacteristic returned false at chunk ${i + 1}/${chunks.size} -> disconnect for recovery")
                    if (isResponseCmd) Log.w(TAG, "ANDROID_RESPONSE_RESULT writeCharacteristic=false at chunk ${i + 1}")
                    try { gatt.disconnect() } catch (_: Exception) {}
                    return
                }

                // even without callback, hold "in flight" for pacing
                writeInFlight = true
                writeHandler.postDelayed({
                    writeInFlight = false
                    sendChunk(i + 1)
                }, perChunkDelayMs)
            }

            sendChunk(0)
        }

        private fun enableNotifications(characteristic: BluetoothGattCharacteristic?) {
            val gatt = bluetoothGatt ?: return
            val chr = characteristic ?: return

            val okSet = gatt.setCharacteristicNotification(chr, true)
            Log.d(TAG, "enableNotifications: setCharacteristicNotification(uuid=${chr.uuid}) -> $okSet")

            val cccd = chr.getDescriptor(CCC_DESCRIPTOR_UUID)
            if (cccd != null) {
                cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                val started = gatt.writeDescriptor(cccd)
                Log.d(TAG, "enableNotifications: writeDescriptor started=$started for descriptor=${cccd.uuid}")
            } else {
                Log.w(TAG, "enableNotifications: CCCD descriptor not found for ${chr.uuid}")
            }
        }

        private fun handleIncomingLine(line: String) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) return

            Log.d(TAG, "handleIncomingLine: '$trimmed'")

            eventCallback(
                mapOf(
                    "type" to "line",
                    "data" to trimmed
                )
            )

            val pr = pendingRequest
            if (pr != null && !pr.completed) {
                pr.collected.add(trimmed)
                val token = trimmed.split(Regex("\\s+")).firstOrNull()?.uppercase() ?: ""
                if (token == "OK" || token == "ERROR") {
                    // Diagnostic: if this OK/ERROR closes a response= command, log it
                    if (awaitingResponseOk) {
                        awaitingResponseOk = false
                        Log.d(TAG, "ANDROID_RESPONSE_RESULT result=$token forCommand=response=")
                    }
                    pr.completed = true
                    pendingRequest = null
                    try {
                        pr.result.success(ArrayList(pr.collected))
                    } catch (_: Exception) {}
                }
            }
        }

        private val gattCallback: BluetoothGattCallback = object : BluetoothGattCallback() {

            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                super.onConnectionStateChange(gatt, status, newState)

                Log.d(TAG, "onConnectionStateChange: status=$status, newState=$newState")

                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> {
                        Log.i(TAG, "onConnectionStateChange: connected, requesting priority + MTU + services")

                        eventCallback(
                            mapOf(
                                "type" to "state",
                                "state" to "CONNECTED",
                                "deviceId" to gatt.device.address
                            )
                        )

                        // ✅ Fix 1: Connection priority HIGH
                        try { gatt.requestConnectionPriority(BluetoothGatt.CONNECTION_PRIORITY_HIGH) } catch (_: Exception) {}

                        // ✅ Optional: lock PHY to 1M (sometimes stabilizes budget devices)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            try {
                                gatt.setPreferredPhy(
                                    BluetoothDevice.PHY_LE_1M_MASK,
                                    BluetoothDevice.PHY_LE_1M_MASK,
                                    0
                                )
                            } catch (_: Exception) {}
                        }

                        // ✅ Fix 2: Less aggressive MTU than 247 (Samsung A03s often behaves better)
                        if (!gatt.requestMtu(185)) {
                            Log.w(TAG, "requestMtu(185) returned false, discovering services directly")
                            gatt.discoverServices()
                        }
                    }

                    BluetoothProfile.STATE_DISCONNECTED -> {
                        Log.i(TAG, "onConnectionStateChange: disconnected (status=$status)")
                        if (bluetoothGatt == gatt) {
                            try { gatt.close() } catch (_: Exception) {}
                            bluetoothGatt = null
                            rxCharacteristic = null
                            txCharacteristic = null
                        }
                        eventCallback(mapOf("type" to "state", "state" to "DISCONNECTED"))
                    }

                    else -> {
                        Log.w(TAG, "onConnectionStateChange: unexpected state $newState")
                    }
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                super.onMtuChanged(gatt, mtu, status)
                Log.d(TAG, "onMtuChanged: mtu=$mtu status=$status")
                gatt.discoverServices()
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                super.onServicesDiscovered(gatt, status)

                Log.d(TAG, "onServicesDiscovered: status=$status")

                if (status != BluetoothGatt.GATT_SUCCESS) {
                    Log.w(TAG, "onServicesDiscovered: failed with status $status")
                    completePendingConnectError("DISCOVER_FAILED", "Service discovery failed: status=$status")
                    gatt.disconnect()
                    return
                }

                val service = gatt.getService(UART_SERVICE_UUID)
                if (service == null) {
                    Log.w(TAG, "onServicesDiscovered: UART service not found")
                    completePendingConnectError("NO_UART", "UART service not found")
                    gatt.disconnect()
                    return
                }

                rxCharacteristic = service.getCharacteristic(UART_RX_UUID)
                txCharacteristic = service.getCharacteristic(UART_TX_UUID)

                val rx = rxCharacteristic
                val tx = txCharacteristic

                if (rx == null || tx == null) {
                    Log.w(TAG, "onServicesDiscovered: UART characteristics not found (rx=$rx, tx=$tx)")
                    completePendingConnectError("NO_UART_CHARS", "UART characteristics not found")
                    gatt.disconnect()
                    return
                }

                Log.d(TAG, "UART RX (write) -> uuid=${rx.uuid}, props=0x${rx.properties.toString(16)}")
                Log.d(TAG, "UART TX (notify) -> uuid=${tx.uuid}, props=0x${tx.properties.toString(16)}")

                // Wait for CCC descriptor to be written before completing connect.
                awaitingCccd = true
                enableNotifications(tx)
                // Safety timeout: if onDescriptorWrite never arrives, fail the connect
                handler.postDelayed({
                    if (awaitingCccd) {
                        Log.w(TAG, "CCCD enable timeout -> disconnect")
                        awaitingCccd = false
                        completePendingConnectError("CCCD_TIMEOUT", "Notifications enable timeout")
                        try { gatt.disconnect() } catch (_: Exception) {}
                    }
                }, 3000L)
            }

            override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                super.onCharacteristicChanged(gatt, characteristic)

                if (characteristic.uuid == UART_TX_UUID) {
                    val data = characteristic.value ?: return
                    val text = String(data, Charsets.UTF_8)
                    val hex = data.joinToString(" ") { b -> "%02X".format(b) }

                    Log.d(TAG, "onCharacteristicChanged: rawText='$text', rawHex=$hex")

                    incomingBuffer.append(text)

                    var newlineIndex = incomingBuffer.indexOf("\n")
                    while (newlineIndex >= 0) {
                        val line = incomingBuffer.substring(0, newlineIndex).trimEnd('\r')
                        if (line.isNotEmpty()) {
                            handleIncomingLine(line)
                        }
                        incomingBuffer.delete(0, newlineIndex + 1)
                        newlineIndex = incomingBuffer.indexOf("\n")
                    }
                }
            }

            override fun onCharacteristicWrite(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                super.onCharacteristicWrite(gatt, characteristic, status)
                // With WRITE_NO_RESPONSE this is not reliable; just log.
                Log.d(TAG, "onCharacteristicWrite: uuid=${characteristic.uuid}, status=$status")
            }

            override fun onDescriptorWrite(gatt: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
                super.onDescriptorWrite(gatt, descriptor, status)

                Log.d(TAG, "onDescriptorWrite: descriptor=${descriptor.uuid}, status=$status")

                if (descriptor.uuid == CCC_DESCRIPTOR_UUID) {
                    if (status == BluetoothGatt.GATT_SUCCESS) {
                        Log.i(TAG, "Notifications enabled on ${descriptor.characteristic.uuid}")
                        if (awaitingCccd) {
                            awaitingCccd = false
                            completePendingConnectSuccess()
                        }
                    } else {
                        Log.w(TAG, "onDescriptorWrite: enabling notifications failed with status=$status")
                        if (awaitingCccd) {
                            awaitingCccd = false
                            completePendingConnectError("CCC_WRITE_FAILED", "CCC descriptor write failed: status=$status")
                            try { gatt.disconnect() } catch (_: Exception) {}
                        }
                    }
                }
            }
        }
    }
}
