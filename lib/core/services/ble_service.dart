import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../config/app_config.dart';

enum BleFailureReason {
  bluetoothOff,
  permissionDenied,
  deviceNotFound,
  wrongDevice,
  outOfRange,
  timeout,
  unsupported,
}

class BleVerificationResult {
  final bool isSuccess;
  final BleFailureReason? failureReason;
  final String message;
  final String? deviceId;
  final String? deviceName;
  final int? rssi;
  final String? token;

  BleVerificationResult.success({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    required this.token,
    this.message = 'Group session organizer Bluetooth proximity verified.',
  })  : isSuccess = true,
        failureReason = null;

  BleVerificationResult.failure({
    required this.failureReason,
    required this.message,
    this.deviceId,
    this.deviceName,
    this.rssi,
    this.token,
  }) : isSuccess = false;
}

class BleScanResult {
  final String deviceId;
  final String deviceName;
  final int rssi;
  final String? discoveredToken;
  final String? discoveredSessionCode;
  final bool isUuidMatch;
  final DateTime timestamp;

  BleScanResult({
    required this.deviceId,
    required this.deviceName,
    required this.rssi,
    this.discoveredToken,
    this.discoveredSessionCode,
    this.isUuidMatch = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  static const MethodChannel _advertiserChannel =
      MethodChannel('com.herenow.app/ble_advertiser');

  // Scanner State
  bool _isScanning = false;
  bool get isScanning => _isScanning;

  int _discoveredDeviceCount = 0;
  int get discoveredDeviceCount => _discoveredDeviceCount;

  int _matchingDeviceCount = 0;
  int get matchingDeviceCount => _matchingDeviceCount;

  int? _lastDiscoveredRssi;
  int? get lastDiscoveredRssi => _lastDiscoveredRssi;

  bool _isSessionMatched = false;
  bool get isSessionMatched => _isSessionMatched;

  bool _isTokenMatched = false;
  bool get isTokenMatched => _isTokenMatched;

  bool _isProximityMet = false;
  bool get isProximityMet => _isProximityMet;

  // Advertiser State
  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  String? _advertisingServiceUuid;
  String? get advertisingServiceUuid => _advertisingServiceUuid;

  String? _advertisingSessionCode;
  String? get advertisingSessionCode => _advertisingSessionCode;

  String? _advertisingToken;
  String? get advertisingToken => _advertisingToken;

  final StreamController<BleScanResult> _discoveryStreamController =
      StreamController<BleScanResult>.broadcast();
  Stream<BleScanResult> get discoveryStream => _discoveryStreamController.stream;

  StreamSubscription? _scanSubscription;

  // RSSI smoothing buffer: token -> list of recent RSSI samples
  final Map<String, List<int>> _rssiSampleBuffer = {};

  // Test overrides for deterministic unit and widget testing
  static bool? testBluetoothAvailable;
  static bool? testPermissionGranted;
  static List<BleScanResult>? testDiscoveredDevices;
  static bool? testForceTimeout;
  static int? testForceRssi;

  static void resetTestOverrides() {
    testBluetoothAvailable = null;
    testPermissionGranted = null;
    testDiscoveredDevices = null;
    testForceTimeout = null;
    testForceRssi = null;
  }

  /// Check if BLE is supported on the current running host
  bool get isNativeBleSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  /// Check if BLE advertising is supported by the device hardware
  Future<bool> isAdvertisingSupported() async {
    if (testBluetoothAvailable != null) {
      return testBluetoothAvailable!;
    }
    if (!kIsWeb && Platform.isAndroid) {
      try {
        final status = await _advertiserChannel.invokeMapMethod<String, dynamic>('getAdvertisingStatus');
        final supported = status?['supported'] == true;
        debugPrint('[HereNowBle] Native advertising supported: $supported');
        return supported;
      } catch (e) {
        debugPrint('[HereNowBle] Error querying advertising support: $e');
        return false;
      }
    }
    return isNativeBleSupported;
  }

  /// Request runtime Bluetooth and Location permissions appropriate for the Android API level
  Future<bool> requestPermissions() async {
    if (testPermissionGranted != null) {
      return testPermissionGranted!;
    }
    if (!isNativeBleSupported) return true;
    try {
      if (Platform.isAndroid) {
        // Modern Android 12+ (API 31+) permissions
        final scan = await Permission.bluetoothScan.request();
        final connect = await Permission.bluetoothConnect.request();
        final advertise = await Permission.bluetoothAdvertise.request();

        // Location permission (required on Android <= 11 and for beacons on Android 12+)
        var locStatus = await Permission.location.status;
        if (locStatus.isDenied) {
          locStatus = await Permission.location.request();
        }

        final isScanOk = scan.isGranted || scan.isLimited;
        final isAdvOk = advertise.isGranted || advertise.isLimited;
        final isLocOk = locStatus.isGranted || locStatus.isLimited;

        debugPrint('[HereNowBle] Android permissions: scan=$isScanOk, adv=$isAdvOk, connect=${connect.isGranted}, loc=$isLocOk');

        // Bug #5 fix: Use AND for scan+advertise so we don't falsely pass when
        // only one permission is granted. A member needs BLUETOOTH_SCAN; an
        // organizer needs BLUETOOTH_ADVERTISE. Both roles need at least scan to
        // detect the adapter. Return true only if the minimum scan permission is
        // present OR if we at least got advertise (organizer-only path).
        // On Android <=11, runtime BLE perms are not enforced — location suffices.
        return (isScanOk && isAdvOk) || (isScanOk && isLocOk) || isAdvOk;
      } else if (Platform.isIOS || Platform.isMacOS) {
        final bt = await Permission.bluetooth.request();
        return bt.isGranted;
      }
    } catch (e) {
      debugPrint('[HereNowBle] requestPermissions error: $e');
    }
    return true;
  }

  /// Check Bluetooth adapter status
  Future<bool> isBluetoothAvailable() async {
    if (testBluetoothAvailable != null) {
      return testBluetoothAvailable!;
    }
    if (!isNativeBleSupported) return true;
    try {
      final isSupported = await FlutterBluePlus.isSupported;
      if (!isSupported) return false;
      final state = await FlutterBluePlus.adapterState.first;
      return state == BluetoothAdapterState.on;
    } catch (e) {
      debugPrint('[HereNowBle] Adapter check notice: $e');
      return false;
    }
  }

  /// Request Bluetooth to turn on if supported (Android only)
  Future<void> turnOnBluetooth() async {
    if (isNativeBleSupported) {
      try {
        if (!kIsWeb && Platform.isAndroid) {
          await FlutterBluePlus.turnOn();
        }
      } catch (e) {
        debugPrint('[HereNowBle] turnOnBluetooth error: $e');
      }
    }
  }

  // ===========================================================================
  // ORGANIZER BLE ADVERTISER
  // ===========================================================================

  /// Start BLE advertising from the Organizer device
  Future<bool> startAdvertising({
    required String serviceUuid,
    required String sessionCode,
    required String token,
    String? customName,
  }) async {
    debugPrint('[HereNowBleAdvertiser] Initiating startAdvertising: UUID=$serviceUuid, sessionCode=$sessionCode');

    final btOn = await isBluetoothAvailable();
    if (!btOn) {
      debugPrint('[HereNowBleAdvertiser] Cannot advertise: Bluetooth is OFF');
      _isAdvertising = false;
      return false;
    }

    final hasPerm = await requestPermissions();
    if (!hasPerm) {
      debugPrint('[HereNowBleAdvertiser] Cannot advertise: Bluetooth permissions not granted');
      _isAdvertising = false;
      return false;
    }

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final result = await _advertiserChannel.invokeMethod<bool>('startAdvertising', {
          'serviceUuid': serviceUuid,
          'sessionCode': sessionCode,
          'token': token,
          'customName': customName ?? 'HN_${sessionCode.replaceAll("HN-", "")}',
        });

        _isAdvertising = result == true;
        _advertisingServiceUuid = serviceUuid;
        _advertisingSessionCode = sessionCode;
        _advertisingToken = token;
        debugPrint('[HereNowBleAdvertiser] Advertising ACTIVE: $_isAdvertising');
        return _isAdvertising;
      } catch (e) {
        debugPrint('[HereNowBleAdvertiser] Exception during startAdvertising: $e');
        _isAdvertising = false;
        return false;
      }
    }

    // In unit tests / simulated environments
    _isAdvertising = true;
    _advertisingServiceUuid = serviceUuid;
    _advertisingSessionCode = sessionCode;
    _advertisingToken = token;
    return true;
  }

  /// Stop BLE advertising
  Future<void> stopAdvertising() async {
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _advertiserChannel.invokeMethod('stopAdvertising');
      } catch (e) {
        debugPrint('[HereNowBleAdvertiser] stopAdvertising error: $e');
      }
    }
    _isAdvertising = false;
    _advertisingServiceUuid = null;
    _advertisingSessionCode = null;
    _advertisingToken = null;
    debugPrint('[HereNowBleAdvertiser] Advertising INACTIVE');
  }

  // ===========================================================================
  // MEMBER BLE SCANNER & PROXIMITY DETECTION
  // ===========================================================================

  /// Calculate filtered/smoothed average RSSI from rolling window samples
  int calculateSmoothedRssi(String tokenKey, int latestRssi) {
    final buffer = _rssiSampleBuffer.putIfAbsent(tokenKey, () => []);
    buffer.add(latestRssi);
    if (buffer.length > 5) {
      buffer.removeAt(0); // keep 5 most recent samples
    }
    final sum = buffer.reduce((a, b) => a + b);
    return (sum / buffer.length).round();
  }

  /// Scans for and verifies the active group organizer session beacon within the required proximity threshold.
  /// Collects multiple samples over a short stability window before marking proximity verified.
  Future<BleVerificationResult> scanAndVerifyPresenceDevice({
    required String expectedToken,
    String? expectedSessionCode,
    int proximityThresholdRssi = AppConfig.defaultProximityRssi,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    // Bug #9 fix: Clear stale state from any previous scan cycle before starting fresh.
    // Prevents old token/RSSI data from the broadcast stream causing false positives.
    clearRssiBuffer();
    _isSessionMatched = false;
    _isTokenMatched = false;
    _isProximityMet = false;

    // 1. Adapter check
    final isBtOn = await isBluetoothAvailable();
    if (!isBtOn) {
      return BleVerificationResult.failure(
        failureReason: BleFailureReason.bluetoothOff,
        message: 'Bluetooth is turned off. Please turn on Bluetooth to verify presence.',
      );
    }

    // 2. Permission check
    final hasPerm = await requestPermissions();
    if (!hasPerm) {
      return BleVerificationResult.failure(
        failureReason: BleFailureReason.permissionDenied,
        message: 'Bluetooth permission denied. Bluetooth access is required to detect the group organizer.',
      );
    }

    // 3. Test overrides
    if (testForceTimeout == true) {
      return BleVerificationResult.failure(
        failureReason: BleFailureReason.timeout,
        message: 'Bluetooth verification timed out while searching for the group organizer device.',
      );
    }

    if (testDiscoveredDevices != null) {
      final list = testDiscoveredDevices!;
      if (list.isEmpty) {
        return BleVerificationResult.failure(
          failureReason: BleFailureReason.deviceNotFound,
          message: 'No group session organizer device found nearby.',
        );
      }

      for (final dev in list) {
        final matchesToken = dev.discoveredToken == expectedToken || dev.deviceName.contains(expectedToken);
        final matchesSession = expectedSessionCode == null ||
            dev.discoveredSessionCode == expectedSessionCode ||
            dev.deviceName.contains(expectedSessionCode.replaceAll('HN-', ''));

        if (matchesToken || matchesSession) {
          _isSessionMatched = true;
          _isTokenMatched = true;
          _matchingDeviceCount++;
          final effectiveRssi = testForceRssi ?? dev.rssi;
          _lastDiscoveredRssi = effectiveRssi;
          final smoothedRssi = calculateSmoothedRssi(expectedToken, effectiveRssi);

          if (smoothedRssi < proximityThresholdRssi) {
            _isProximityMet = false;
            return BleVerificationResult.failure(
              failureReason: BleFailureReason.outOfRange,
              message: 'Organizer Bluetooth detected, but signal is too weak (RSSI: ${smoothedRssi} dBm, required: >= ${proximityThresholdRssi} dBm). Please move closer.',
              deviceId: dev.deviceId,
              deviceName: dev.deviceName,
              rssi: smoothedRssi,
              token: expectedToken,
            );
          }

          _isProximityMet = true;
          return BleVerificationResult.success(
            deviceId: dev.deviceId,
            deviceName: dev.deviceName,
            rssi: smoothedRssi,
            token: expectedToken,
          );
        }
      }

      return BleVerificationResult.failure(
        failureReason: BleFailureReason.wrongDevice,
        message: 'Wrong Bluetooth device detected. The nearby device does not belong to the active group session.',
      );
    }

    // 4. Real Native BLE Scanning
    if (isNativeBleSupported) {
      final completer = Completer<BleVerificationResult>();
      final List<int> detectedSamples = [];
      String? matchedDeviceId;
      String? matchedDeviceName;
      StreamSubscription? sub;

      final normalizedSession = (expectedSessionCode ?? '').replaceAll('HN-', '').toUpperCase().trim();
      final expectedUuidLower = AppConfig.bleServiceUuid.toLowerCase();

      sub = discoveryStream.listen((res) {
        final hasToken = res.discoveredToken == expectedToken;
        final hasSession = normalizedSession.isNotEmpty &&
            (res.discoveredSessionCode == normalizedSession ||
                res.deviceName.contains(normalizedSession));
        final hasUuid = res.isUuidMatch;

        if (hasToken || (hasUuid && hasSession) || (hasToken && hasSession)) {
          _isSessionMatched = true;
          _isTokenMatched = true;
          _matchingDeviceCount++;
          _lastDiscoveredRssi = res.rssi;
          matchedDeviceId = res.deviceId;
          matchedDeviceName = res.deviceName;

          detectedSamples.add(res.rssi);
          final smoothedRssi = calculateSmoothedRssi(expectedToken, res.rssi);

          debugPrint('[HereNowBle] Valid detection sample #${detectedSamples.length}: RSSI=${res.rssi} dBm, smoothed=$smoothedRssi dBm');

          // Stability window: 2 valid detections to prevent transient spikes
          if (detectedSamples.length >= 2 && smoothedRssi >= proximityThresholdRssi) {
            _isProximityMet = true;
            if (!completer.isCompleted) {
              debugPrint('[HereNowBle] Proximity threshold MET ($smoothedRssi >= $proximityThresholdRssi dBm) with ${detectedSamples.length} samples!');
              // Bug #3 fix: Cancel stream listener and stop scan immediately on success
              // instead of waiting for the timeout timer — saves battery and resets state.
              sub?.cancel();
              stopScan();
              completer.complete(BleVerificationResult.success(
                deviceId: res.deviceId,
                deviceName: res.deviceName,
                rssi: smoothedRssi,
                token: expectedToken,
              ));
            }
          }
        }
      });

      await startPresenceScan(
        activeToken: expectedToken,
        activeSessionCode: expectedSessionCode,
        duration: timeout,
      );

      Timer(timeout, () {
        if (!completer.isCompleted) {
          if (detectedSamples.isNotEmpty) {
            final avg = (detectedSamples.reduce((a, b) => a + b) / detectedSamples.length).round();
            _lastDiscoveredRssi = avg;
            if (avg >= proximityThresholdRssi) {
              _isProximityMet = true;
              completer.complete(BleVerificationResult.success(
                deviceId: matchedDeviceId,
                deviceName: matchedDeviceName,
                rssi: avg,
                token: expectedToken,
              ));
            } else {
              _isProximityMet = false;
              completer.complete(BleVerificationResult.failure(
                failureReason: BleFailureReason.outOfRange,
                message: 'Organizer detected, but outside required proximity range (RSSI: $avg dBm, required >= $proximityThresholdRssi dBm). Move closer.',
                deviceId: matchedDeviceId,
                deviceName: matchedDeviceName,
                rssi: avg,
                token: expectedToken,
              ));
            }
          } else if (_discoveredDeviceCount > 0) {
            completer.complete(BleVerificationResult.failure(
              failureReason: BleFailureReason.wrongDevice,
              message: 'Detected nearby Bluetooth devices do not match the active group session.',
            ));
          } else {
            completer.complete(BleVerificationResult.failure(
              failureReason: BleFailureReason.deviceNotFound,
              message: 'No organizer device found nearby within the scan window.',
            ));
          }
        }
        // Bug #3 fix: Always stop the scan and cancel the discovery listener when the
        // timeout fires, regardless of completer outcome. This eliminates the race where
        // startPresenceScan's own internal stopScan timer could fire first and cut off
        // the scan before this timer had a chance to read results.
        sub?.cancel();
        stopScan();
      });

      return completer.future;
    }

    return BleVerificationResult.failure(
      failureReason: BleFailureReason.deviceNotFound,
      message: 'No group session organizer device found nearby.',
    );
  }

  /// Backward-compatibility alias
  Future<BleVerificationResult> scanAndVerifyClassroomDevice({
    required String expectedToken,
    int proximityThresholdRssi = AppConfig.defaultProximityRssi,
    Duration timeout = const Duration(seconds: 4),
  }) =>
      scanAndVerifyPresenceDevice(
        expectedToken: expectedToken,
        proximityThresholdRssi: proximityThresholdRssi,
        timeout: timeout,
      );

  /// Member starts scanning for organizer presence advertisement
  Future<void> startPresenceScan({
    required String activeToken,
    String? activeSessionCode,
    Duration duration = const Duration(seconds: 8),
  }) async {
    if (_isScanning) return;
    _isScanning = true;
    _discoveredDeviceCount = 0;
    _matchingDeviceCount = 0;

    await requestPermissions();

    if (isNativeBleSupported) {
      try {
        await _scanSubscription?.cancel();

        try {
          final adapterState = await FlutterBluePlus.adapterState.first;
          if (adapterState != BluetoothAdapterState.on && Platform.isAndroid) {
            await turnOnBluetooth();
          }
        } catch (_) {}

        final expectedUuidLower = AppConfig.bleServiceUuid.toLowerCase();
        final cleanSessionCode = (activeSessionCode ?? '').replaceAll('HN-', '').toUpperCase().trim();

        _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
          _discoveredDeviceCount = results.length;
          for (final result in results) {
            final deviceName = result.device.platformName.isNotEmpty
                ? result.device.platformName
                : result.advertisementData.advName;

            bool isUuidMatch = false;
            for (final u in result.advertisementData.serviceUuids) {
              if (u.str128.toLowerCase() == expectedUuidLower) {
                isUuidMatch = true;
                break;
              }
            }

            String? tokenFound;
            String? sessionCodeFound;

            // Check manufacturer data
            for (final entry in result.advertisementData.manufacturerData.entries) {
              final rawStr = String.fromCharCodes(entry.value);
              if (rawStr.contains(activeToken)) {
                tokenFound = activeToken;
              }
              if (cleanSessionCode.isNotEmpty && rawStr.contains(cleanSessionCode)) {
                sessionCodeFound = cleanSessionCode;
              }
              if (rawStr.startsWith('HN:')) {
                final parts = rawStr.split(':');
                if (parts.length >= 2 && parts[1].isNotEmpty) {
                  sessionCodeFound = parts[1];
                }
                if (parts.length >= 3 && parts[2].isNotEmpty) {
                  tokenFound = parts[2];
                }
              }
            }

            // Check service data
            for (final data in result.advertisementData.serviceData.values) {
              final str = String.fromCharCodes(data);
              if (str.contains(activeToken)) {
                tokenFound = activeToken;
              }
              if (cleanSessionCode.isNotEmpty && str.contains(cleanSessionCode)) {
                sessionCodeFound = cleanSessionCode;
              }
            }

            // Check device name
            if (deviceName.startsWith('HN_') || deviceName.contains(activeToken)) {
              tokenFound = activeToken;
            }
            if (cleanSessionCode.isNotEmpty && deviceName.contains(cleanSessionCode)) {
              sessionCodeFound = cleanSessionCode;
            }

            if (isUuidMatch || tokenFound != null || sessionCodeFound != null) {
              debugPrint('[HereNowBle] Discovered Organizer Beacon! Device: ${result.device.remoteId.str}, Name: "$deviceName", RSSI: ${result.rssi} dBm, UUID match: $isUuidMatch, Token: $tokenFound, Session: $sessionCodeFound');
            }

            _discoveryStreamController.add(BleScanResult(
              deviceId: result.device.remoteId.str,
              deviceName: deviceName.isNotEmpty ? deviceName : 'Nearby BLE Device',
              rssi: result.rssi,
              discoveredToken: tokenFound,
              discoveredSessionCode: sessionCodeFound,
              isUuidMatch: isUuidMatch,
            ));
          }
        });

        // Use active scanning. androidUsesFineLocation=false aligns with the
        // neverForLocation flag in AndroidManifest.xml — using true would contradict
        // it and can cause silent scan failures on battery-restricted devices.
        await FlutterBluePlus.startScan(
          timeout: duration,
          androidUsesFineLocation: false,
        );
      } catch (e) {
        debugPrint('[HereNowBle] Native scan error: $e');
        // Bug #2 fix: Reset _isScanning on any exception so future scan attempts
        // are not permanently blocked. Previously a crash here left _isScanning=true
        // forever, requiring an app restart to recover BLE.
        _isScanning = false;
      }
    }
    // Bug #3 fix: Removed the redundant Timer(duration, stopScan) that was here.
    // scanAndVerifyPresenceDevice's own timeout timer now owns cleanup exclusively,
    // eliminating the race where both timers fired at the same moment.
  }

  /// Backward-compatibility alias
  Future<bool> listenForOrganizerCheck({
    required String expectedToken,
    int proximityThresholdRssi = AppConfig.defaultProximityRssi,
    Duration duration = const Duration(seconds: 4),
  }) async {
    final result = await scanAndVerifyPresenceDevice(
      expectedToken: expectedToken,
      proximityThresholdRssi: proximityThresholdRssi,
      timeout: duration,
    );
    return result.isSuccess;
  }

  /// Stop any active BLE scan
  Future<void> stopScan() async {
    _isScanning = false;
    try {
      if (isNativeBleSupported) {
        await FlutterBluePlus.stopScan();
      }
      await _scanSubscription?.cancel();
      _scanSubscription = null;
    } catch (e) {
      debugPrint('[HereNowBle] stopScan error: $e');
    }
  }

  /// Clear RSSI buffer for new checks
  void clearRssiBuffer() {
    _rssiSampleBuffer.clear();
    _discoveredDeviceCount = 0;
    _matchingDeviceCount = 0;
    _lastDiscoveredRssi = null;
    _isSessionMatched = false;
    _isTokenMatched = false;
    _isProximityMet = false;
  }

  /// Simulate detection pulse for demo, emulators, or test environments
  void simulateMemberDetection({
    required String memberId,
    required String memberName,
    required String token,
    int rssi = -65,
  }) {
    _discoveryStreamController.add(BleScanResult(
      deviceId: 'sim_$memberId',
      deviceName: memberName,
      rssi: rssi,
      discoveredToken: token,
      isUuidMatch: true,
    ));
  }

  void dispose() {
    stopAdvertising();
    _scanSubscription?.cancel();
    _discoveryStreamController.close();
  }
}
