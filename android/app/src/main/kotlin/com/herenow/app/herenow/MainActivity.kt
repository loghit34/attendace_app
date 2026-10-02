package com.herenow.app.herenow

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.os.Build
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.nio.charset.StandardCharsets

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.herenow.app/ble_advertiser"
    private val TAG = "HereNowBleAdvertiser"

    private var advertiser: BluetoothLeAdvertiser? = null
    private var isAdvertising = false
    private var activeCallback: AdvertiseCallback? = null
    private var lastServiceUuid: String? = null
    private var lastSessionCode: String? = null
    private var lastToken: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAdvertisingStatus" -> {
                    val status = checkAdvertisingStatus()
                    result.success(status)
                }
                "startAdvertising" -> {
                    val serviceUuidStr = call.argument<String>("serviceUuid") ?: "8f331900-1122-3344-5566-778899aabbcc"
                    val sessionCode = call.argument<String>("sessionCode") ?: ""
                    val token = call.argument<String>("token") ?: ""
                    val customName = call.argument<String>("customName") ?: ""

                    startBleAdvertising(serviceUuidStr, sessionCode, token, customName, result)
                }
                "stopAdvertising" -> {
                    stopBleAdvertising()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getBluetoothAdapter(): BluetoothAdapter? {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        return bluetoothManager?.adapter ?: BluetoothAdapter.getDefaultAdapter()
    }

    private fun checkAdvertisingStatus(): Map<String, Any> {
        val adapter = getBluetoothAdapter()
        val isEnabled = adapter?.isEnabled == true
        val isSupported = adapter != null && (adapter.isMultipleAdvertisementSupported || adapter.bluetoothLeAdvertiser != null)
        val hasAdvertiser = adapter?.bluetoothLeAdvertiser != null

        Log.d(TAG, "checkAdvertisingStatus: enabled=$isEnabled, supported=$isSupported, hasAdvertiser=$hasAdvertiser, isAdvertising=$isAdvertising")

        return mapOf(
            "supported" to isSupported,
            "enabled" to isEnabled,
            "hasAdvertiser" to hasAdvertiser,
            "isAdvertising" to isAdvertising,
            "serviceUuid" to (lastServiceUuid ?: ""),
            "sessionCode" to (lastSessionCode ?: ""),
            "tokenActive" to (lastToken != null && lastToken!!.isNotEmpty())
        )
    }

    private fun startBleAdvertising(
        serviceUuidStr: String,
        sessionCode: String,
        token: String,
        customName: String,
        result: MethodChannel.Result
    ) {
        val adapter = getBluetoothAdapter()
        if (adapter == null || !adapter.isEnabled) {
            Log.e(TAG, "Cannot start BLE advertising: Bluetooth is disabled or adapter is null")
            result.error("BLUETOOTH_OFF", "Bluetooth is turned off on the device.", null)
            return
        }

        advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.e(TAG, "Cannot start BLE advertising: BluetoothLeAdvertiser is not supported on this device")
            result.error("UNSUPPORTED", "Device hardware does not support BLE advertising.", null)
            return
        }

        // Stop any currently running advertisement before starting a new one
        stopBleAdvertising()

        try {
            val settings = AdvertiseSettings.Builder()
                .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                .setConnectable(false)
                .setTimeout(0) // Run until explicitly stopped
                .build()

            val serviceUuid = ParcelUuid.fromString(serviceUuidStr)

            // Primary packet: Service UUID (21 bytes total with flags <= 31 bytes)
            val advData = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addServiceUuid(serviceUuid)
                .build()

            // Build compact payload for Scan Response: "HN:<code6>:<token16>"
            val cleanCode = sessionCode.replace("HN-", "").trim().take(8)
            val cleanToken = token.trim().take(16)
            val payloadStr = if (cleanCode.isNotEmpty() && cleanToken.isNotEmpty()) {
                "HN:$cleanCode:$cleanToken"
            } else if (cleanToken.isNotEmpty()) {
                "HN:$cleanToken"
            } else {
                "HN:$cleanCode"
            }

            // Manufacturer Data (Company ID 0xFFFF: 2 bytes header + 2 bytes ID + payload <= 31 bytes)
            val payloadBytes = payloadStr.toByteArray(StandardCharsets.UTF_8)
            val scanResponse = AdvertiseData.Builder()
                .setIncludeDeviceName(false)
                .setIncludeTxPowerLevel(false)
                .addManufacturerData(0xFFFF, payloadBytes)
                .build()

            val callback = object : AdvertiseCallback() {
                override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                    super.onStartSuccess(settingsInEffect)
                    isAdvertising = true
                    lastServiceUuid = serviceUuidStr
                    lastSessionCode = sessionCode
                    lastToken = token
                    Log.i(TAG, "✓ BLE Advertising successfully ACTIVE! Service UUID: $serviceUuidStr, Session: $sessionCode, Payload: $payloadStr")
                    try {
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w(TAG, "Callback result already sent: ${e.message}")
                    }
                }

                override fun onStartFailure(errorCode: Int) {
                    super.onStartFailure(errorCode)
                    isAdvertising = false
                    val errorMsg = when (errorCode) {
                        ADVERTISE_FAILED_DATA_TOO_LARGE -> "Advertise packet too large (>31 bytes)"
                        ADVERTISE_FAILED_TOO_MANY_ADVERTISERS -> "Too many active BLE advertisers"
                        ADVERTISE_FAILED_ALREADY_STARTED -> "Advertising already active"
                        ADVERTISE_FAILED_INTERNAL_ERROR -> "Internal BLE controller error"
                        ADVERTISE_FAILED_FEATURE_UNSUPPORTED -> "Advertising unsupported by hardware"
                        else -> "Advertising failed (code $errorCode)"
                    }
                    Log.e(TAG, "✗ BLE Advertising start failure: $errorMsg (code $errorCode)")
                    try {
                        result.error("ADVERTISE_FAILED", errorMsg, errorCode)
                    } catch (e: Exception) {
                        Log.w(TAG, "Callback result already sent: ${e.message}")
                    }
                }
            }

            activeCallback = callback
            advertiser?.startAdvertising(settings, advData, scanResponse, callback)
            Log.d(TAG, "Initiated startAdvertising on BluetoothLeAdvertiser with UUID: $serviceUuidStr and payload: $payloadStr")
        } catch (e: Exception) {
            Log.e(TAG, "Exception while starting BLE advertisement: ${e.message}", e)
            result.error("EXCEPTION", e.message, null)
        }
    }

    private fun stopBleAdvertising() {
        if (activeCallback != null && advertiser != null) {
            try {
                advertiser?.stopAdvertising(activeCallback)
                Log.i(TAG, "✓ BLE Advertising stopped successfully")
            } catch (e: Exception) {
                Log.w(TAG, "Notice while stopping BLE advertising: ${e.message}")
            }
        }
        activeCallback = null
        isAdvertising = false
    }

    override fun onDestroy() {
        stopBleAdvertising()
        super.onDestroy()
    }
}
