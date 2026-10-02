import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../config/app_config.dart';
import '../models/presence_check_model.dart';
import '../models/presence_event_model.dart';
import '../models/session_member_model.dart';
import '../models/session_model.dart';
import '../models/user_model.dart';
import '../services/ble_service.dart';
import '../services/report_service.dart';
import '../services/session_service.dart';
import '../utils/join_code_helper.dart';

enum PresenceVerificationStatus {
  idle,
  checkingPrerequisites,
  scanningForOrganizer,
  organizerDetected,
  proximityVerified,
  recordingPresence,
  outOfRange,
  success,
  failed,
}

enum BleAdvertiserState {
  inactive,
  starting,
  active,
  error,
}

// Backward compatibility alias
typedef AttendanceVerificationStatus = PresenceVerificationStatus;

class SessionProvider extends ChangeNotifier {
  late SessionService _sessionService;
  final BleService _bleService = BleService();

  SessionModel? _activeSession;
  List<SessionModel> _userSessions = [];
  List<SessionMemberModel> _members = [];
  List<PresenceEventModel> _events = [];
  PresenceCheckModel? _activeCheck;

  bool _isLoading = false;
  bool _isCheckingPresence = false;
  String? _errorMessage;

  // Organizer BLE Advertising State
  BleAdvertiserState _advertiserState = BleAdvertiserState.inactive;
  BleAdvertiserState get advertiserState => _advertiserState;
  bool get isAdvertising => _bleService.isAdvertising;

  // Granular separate states for Universal Presence & Bluetooth proximity verification
  PresenceVerificationStatus _verificationStatus = PresenceVerificationStatus.idle;
  bool _isBluetoothAvailable = true;
  bool _isBluetoothPermissionGranted = true;
  bool _isBluetoothDeviceFound = false;
  bool _isBluetoothDeviceVerified = false;
  bool _isPresenceSessionValid = false;
  bool _isPresenceRecorded = false;
  int? _lastDetectedRssi;
  String? _verificationError;
  String? _verificationStatusMessage;

  StreamSubscription? _membersSub;
  StreamSubscription? _eventsSub;
  StreamSubscription? _bleSub;
  StreamSubscription? _autoScanSub;
  Timer? _checkTimer;
  Timer? _autoScanPollTimer;
  bool _isAutoScanning = false;

  SessionModel? get activeSession => _activeSession;
  List<SessionModel> get userSessions => _userSessions;
  List<SessionMemberModel> get members => _members;
  List<PresenceEventModel> get events => _events;
  PresenceCheckModel? get activeCheck => _activeCheck;
  bool get isLoading => _isLoading;
  bool get isCheckingPresence => _isCheckingPresence;
  String? get errorMessage => _errorMessage;

  // Granular state getters
  PresenceVerificationStatus get verificationStatus => _verificationStatus;
  bool get isBluetoothAvailable => _isBluetoothAvailable;
  bool get isBluetoothPermissionGranted => _isBluetoothPermissionGranted;
  bool get isBluetoothDeviceFound => _isBluetoothDeviceFound;
  bool get isBluetoothDeviceVerified => _isBluetoothDeviceVerified;
  bool get isPresenceSessionValid => _isPresenceSessionValid;
  bool get isPresenceRecorded => _isPresenceRecorded;
  int? get lastDetectedRssi => _lastDetectedRssi;
  String? get verificationError => _verificationError;
  String? get verificationStatusMessage => _verificationStatusMessage;
  bool get isAutoScanning => _isAutoScanning;

  // Backwards compatibility getters
  bool get isAttendanceRecorded => _isPresenceRecorded;
  bool get isAttendanceSessionValid => _isPresenceSessionValid;

  // Headcount metrics
  int get totalCount => _members.length;
  int get presentCount => _members.where((m) =>
      m.status == PresenceStatus.present ||
      m.status == PresenceStatus.manuallyConfirmed).length;
  int get possiblyAwayCount =>
      _members.where((m) => m.status == PresenceStatus.possiblyAway).length;
  int get missingCount =>
      _members.where((m) => m.status == PresenceStatus.missing).length;
  int get leftCount =>
      _members.where((m) => m.status == PresenceStatus.left).length;

  double get presentRatio =>
      totalCount > 0 ? (presentCount / totalCount).clamp(0.0, 1.0) : 0.0;

  bool isMemberEnrolled(String userId) {
    return _members.any((m) => m.userId == userId);
  }

  SessionProvider({SessionService? sessionService}) {
    _sessionService = sessionService ?? SupabaseSessionService();
  }

  void clearSessionState() {
    stopAutoPresenceScan();
    stopOrganizerAdvertising();
    _activeSession = null;
    _userSessions = [];
    _members = [];
    _events = [];
    _activeCheck = null;
    _verificationStatus = PresenceVerificationStatus.idle;
    _isBluetoothDeviceFound = false;
    _isBluetoothDeviceVerified = false;
    _isPresenceRecorded = false;
    _lastDetectedRssi = null;
    _verificationError = null;
    _verificationStatusMessage = null;
    _membersSub?.cancel();
    _eventsSub?.cancel();
    _bleSub?.cancel();
    _checkTimer?.cancel();
    notifyListeners();
  }

  /// Loads real sessions for the authenticated user from Supabase
  Future<void> loadUserSessions(String userId) async {
    _isLoading = true;
    notifyListeners();

    try {
      final sessions = await _sessionService.getUserSessions(userId);
      _userSessions = sessions;
      if (sessions.isNotEmpty) {
        if (_activeSession != null && sessions.any((s) => s.id == _activeSession!.id)) {
          await selectSession(_activeSession!.id);
        } else {
          final activeOrFirst = sessions.firstWhere((s) => s.isActive, orElse: () => sessions.first);
          await selectSession(activeOrFirst.id);
        }
      } else {
        _activeSession = null;
        _members = [];
        _events = [];
      }
    } catch (e) {
      debugPrint('Load sessions note: $e');
      _userSessions = [];
      _activeSession = null;
      _members = [];
      _events = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectSession(String sessionId) async {
    _isLoading = true;
    _verificationStatus = PresenceVerificationStatus.idle;
    _verificationError = null;
    _verificationStatusMessage = null;
    notifyListeners();

    try {
      _activeSession = await _sessionService.getSession(sessionId);
      if (_activeSession != null) {
        _members = await _sessionService.getSessionMembers(sessionId);
        _events = await _sessionService.getSessionEvents(sessionId);

        // Ensure organizer exists in members list
        if (_members.isEmpty && _activeSession != null) {
          _members = [
            SessionMemberModel(
              id: const Uuid().v4(),
              sessionId: _activeSession!.id,
              userId: _activeSession!.organizerId,
              userName: 'Organizer (You)',
              role: 'organizer',
              status: PresenceStatus.present,
              lastVerifiedAt: DateTime.now(),
              joinedAt: DateTime.now(),
            ),
          ];
        }

        // Subscribe to live member updates
        await _membersSub?.cancel();
        try {
          _membersSub = _sessionService.streamSessionMembers(sessionId).listen(
            (updatedList) {
              if (updatedList.isNotEmpty) {
                _members = updatedList;
                notifyListeners();
              }
            },
            onError: (err) {
              debugPrint('Session members stream notice: $err');
            },
          );
        } catch (e) {
          debugPrint('Session stream subscribe notice: $e');
        }

        // Subscribe to live audit events
        await _eventsSub?.cancel();
        try {
          _eventsSub = _sessionService.streamSessionEvents(sessionId).listen(
            (ev) {
              _events.insert(0, ev);
              notifyListeners();
            },
            onError: (err) {
              debugPrint('Session events stream notice: $err');
            },
          );
        } catch (_) {}
      }
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new presence session
  Future<SessionModel?> createSession({
    required String name,
    required String organizerId,
    String? organizerName,
    String category = 'OTHER',
    String? description,
    required DateTime startTime,
    required DateTime endTime,
    ProximityMode proximityMode = ProximityMode.normal,
    double? latitude,
    double? longitude,
    double? geofenceRadius,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final randomCode = 'HN-${100000 + (DateTime.now().microsecond * 899000 ~/ 1000000)}';
      final newSession = SessionModel(
        id: const Uuid().v4(),
        organizerId: organizerId,
        name: name,
        description: description,
        category: category,
        joinCode: randomCode,
        startTime: startTime,
        endTime: endTime,
        proximityMode: proximityMode,
        meetingLatitude: latitude,
        meetingLongitude: longitude,
        geofenceRadius: geofenceRadius,
        status: 'active',
      );

      final created = await _sessionService.createSession(newSession);
      _userSessions.insert(0, created);
      await selectSession(created.id);
      return created;
    } catch (e) {
      _errorMessage = 'Failed to create session: $e';
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Join an existing session with a 6-digit join code or deep link.
  /// Joining ONLY grants enrollment with unverified status (missing).
  /// Joining DOES NOT mark the user present.
  Future<bool> joinSessionByCode({
    required String joinCode,
    required UserModel user,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    final normalized = JoinCodeHelper.normalize(joinCode);
    debugPrint('[Diagnostic] JoinSessionByCode initiated: input="$joinCode", normalized="$normalized", user="${user.name}" (${user.id})');

    try {
      final session = await _sessionService.getSessionByCode(joinCode);
      if (session == null) {
        _errorMessage = 'Session not found. Please check your join code.';
        debugPrint('[Diagnostic] Join failed: Session not found for code "$normalized"');
        return false;
      }

      if (session.isExpired) {
        _errorMessage = 'This session has already expired.';
        debugPrint('[Diagnostic] Join failed: Session ${session.id} has expired (endTime: ${session.endTime})');
        return false;
      }

      if (session.status == 'completed') {
        _errorMessage = 'This session has ended.';
        debugPrint('[Diagnostic] Join failed: Session ${session.id} status is completed');
        return false;
      }

      // Member joins with initial unverified status (PresenceStatus.missing)
      await _sessionService.joinSession(
        sessionId: session.id,
        user: user,
      );

      if (!_userSessions.any((s) => s.id == session.id)) {
        _userSessions.insert(0, session);
      }

      await selectSession(session.id);
      debugPrint('[Diagnostic] Member ${user.name} successfully joined session ${session.id}');
      return true;
    } catch (e) {
      _errorMessage = 'Failed to join session: $e';
      debugPrint('[Diagnostic] Error during joinSessionByCode: $e');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Organizer starts BLE advertising for the active session
  Future<bool> startOrganizerAdvertising({String? organizerId}) async {
    if (_activeSession == null) return false;
    _advertiserState = BleAdvertiserState.starting;
    _isCheckingPresence = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final orgId = organizerId ?? _activeSession!.organizerId;
      var check = _activeCheck;
      if (check == null || check.isExpired) {
        check = await _sessionService.startPresenceCheck(
          sessionId: _activeSession!.id,
          organizerId: orgId,
        );
        _activeCheck = check;
      }

      final success = await _bleService.startAdvertising(
        serviceUuid: AppConfig.bleServiceUuid,
        sessionCode: _activeSession!.joinCode,
        token: check.checkToken,
      );

      if (success) {
        _advertiserState = BleAdvertiserState.active;
        debugPrint('[HereNow] Organizer BLE Advertising ACTIVE for session ${_activeSession!.id}, code=${_activeSession!.joinCode}');
      } else {
        _advertiserState = BleAdvertiserState.error;
        _errorMessage = 'Could not start BLE advertising. Please verify Bluetooth is enabled and permissions granted.';
        debugPrint('[HereNow] Organizer BLE Advertising failed to activate');
      }

      notifyListeners();
      return success;
    } catch (e) {
      _advertiserState = BleAdvertiserState.error;
      _errorMessage = 'Advertising error: $e';
      notifyListeners();
      return false;
    }
  }

  /// Organizer stops BLE advertising
  Future<void> stopOrganizerAdvertising({bool notify = true}) async {
    _advertiserState = BleAdvertiserState.inactive;
    _isCheckingPresence = false;
    await _bleService.stopAdvertising();
    if (notify && hasListeners) {
      notifyListeners();
    }
  }

  /// Organizer starts an active presence check pulse (BLE broadcast)
  Future<void> startPresenceCheck(String organizerId) async {
    if (_activeSession == null) return;
    _isCheckingPresence = true;
    _advertiserState = BleAdvertiserState.starting;
    _errorMessage = null;
    notifyListeners();

    try {
      final check = await _sessionService.startPresenceCheck(
        sessionId: _activeSession!.id,
        organizerId: organizerId,
      );
      _activeCheck = check;

      // Start BLE Advertising with the fresh ephemeral token
      final success = await _bleService.startAdvertising(
        serviceUuid: AppConfig.bleServiceUuid,
        sessionCode: _activeSession!.joinCode,
        token: check.checkToken,
      );

      _advertiserState = success ? BleAdvertiserState.active : BleAdvertiserState.error;
      debugPrint('[HereNow] Organizer presence check initiated: checkId=${check.id}, token=${check.checkToken}, advertisingActive=$success');

      // Simulation for offline demo scenario (Digha trip)
      if (_activeSession?.id == 'session-digha-001') {
        final mockMissing = _members.where((m) => m.userId.startsWith('user-') && m.status == PresenceStatus.missing).toList();
        for (int i = 0; i < mockMissing.length; i++) {
          final member = mockMissing[i];
          Timer(Duration(seconds: 4 + (i * 3)), () {
            if (_isCheckingPresence && _activeCheck?.id == check.id) {
              _bleService.simulateMemberDetection(
                memberId: member.userId,
                memberName: member.userName,
                token: check.checkToken,
                rssi: -58 - (i * 6),
              );
              _sessionService.verifyMemberPresence(
                sessionId: _activeSession!.id,
                checkId: check.id,
                userId: member.userId,
                token: check.checkToken,
                rssi: -58 - (i * 6),
              );
            }
          });
        }
      }

      // Keep advertising active for the check duration
      _checkTimer?.cancel();
      _checkTimer = Timer(AppConfig.scanPulseDuration, () {
        _isCheckingPresence = false;
        notifyListeners();
      });
    } catch (e) {
      _errorMessage = 'Presence check error: $e';
      _isCheckingPresence = false;
      _advertiserState = BleAdvertiserState.error;
    } finally {
      notifyListeners();
    }
  }

  /// Starts continuous automatic BLE proximity detection for a member.
  /// When member physically comes within proximity of the active organizer beacon,
  /// they are automatically verified and marked PRESENT without pressing any button.
  void startAutoPresenceDetection({
    required String userId,
  }) {
    if (_isAutoScanning) return;
    _isAutoScanning = true;

    // Run immediate check
    _runAutoProximityCycle(userId);

    // Run continuous scanning cycle every 5 seconds while active
    _autoScanPollTimer?.cancel();
    _autoScanPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_isAutoScanning && !_isPresenceRecorded) {
        _runAutoProximityCycle(userId);
      }
    });
  }

  Future<void> _runAutoProximityCycle(String userId) async {
    if (_activeSession == null || _isPresenceRecorded) return;

    // Check if user is already verified as present
    final currentMember = _members.cast<SessionMemberModel?>().firstWhere(
      (m) => m != null && m.userId == userId,
      orElse: () => null,
    );

    if (currentMember != null &&
        (currentMember.status == PresenceStatus.present ||
            currentMember.status == PresenceStatus.manuallyConfirmed)) {
      _isPresenceRecorded = true;
      _verificationStatus = PresenceVerificationStatus.success;
      _verificationStatusMessage = '✓ Bluetooth verified\n✓ You are PRESENT';
      notifyListeners();
      return;
    }

    // Check enrollment
    final isEnrolled = _members.any((m) => m.userId == userId);
    if (!isEnrolled) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'You are not enrolled in this group session.';
      notifyListeners();
      return;
    }

    // Fetch active check
    var check = _activeCheck;
    if (check == null || check.isExpired) {
      check = await _sessionService.getActivePresenceCheck(_activeSession!.id);
      _activeCheck = check;
    }

    if (check == null || check.isExpired) {
      _verificationStatus = PresenceVerificationStatus.scanningForOrganizer;
      _verificationStatusMessage = 'Waiting for organizer to start presence check...';
      notifyListeners();
      return;
    }

    // Bluetooth Hardware & Permission Checks
    final btAvailable = await _bleService.isBluetoothAvailable();
    _isBluetoothAvailable = btAvailable;
    if (!btAvailable) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'Bluetooth is turned off. Please turn on Bluetooth.';
      notifyListeners();
      return;
    }

    final permGranted = await _bleService.requestPermissions();
    _isBluetoothPermissionGranted = permGranted;
    if (!permGranted) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'Bluetooth permission denied. Bluetooth access is required for proximity verification.';
      notifyListeners();
      return;
    }

    _verificationStatus = PresenceVerificationStatus.scanningForOrganizer;
    _verificationStatusMessage = 'Scanning for organizer Bluetooth signal...';
    notifyListeners();

    // Scan for organizer beacon with session proximity threshold
    final requiredThreshold = _activeSession?.proximityThresholdRssi ?? AppConfig.defaultProximityRssi;
    final bleResult = await _bleService.scanAndVerifyPresenceDevice(
      expectedToken: check.checkToken,
      expectedSessionCode: _activeSession!.joinCode,
      proximityThresholdRssi: requiredThreshold,
      timeout: const Duration(seconds: 4),
    );

    if (bleResult.isSuccess) {
      _isBluetoothDeviceFound = true;
      _isBluetoothDeviceVerified = true;
      _lastDetectedRssi = bleResult.rssi;
      _verificationStatus = PresenceVerificationStatus.recordingPresence;
      _verificationStatusMessage = 'Proximity verified! Confirming presence with backend...';
      notifyListeners();

      // Bug #7 fix: Re-check _isPresenceRecorded before the backend call.
      // A concurrent Timer.periodic tick can enter this method between the BLE
      // success above and the await below, causing a duplicate verifyMemberPresence call.
      if (_isPresenceRecorded) return;

      // Record presence with backend
      final backendOk = await _sessionService.verifyMemberPresence(
        sessionId: _activeSession!.id,
        checkId: check.id,
        userId: userId,
        token: check.checkToken,
        method: 'ble',
        rssi: bleResult.rssi,
      );

      if (backendOk) {
        _isPresenceRecorded = true;
        _verificationStatus = PresenceVerificationStatus.success;
        _verificationError = null;
        _verificationStatusMessage = '✓ Organizer detected\n✓ Bluetooth proximity verified\n\nYou are PRESENT';
        stopAutoPresenceScan();

        // Update local member cache
        final idx = _members.indexWhere((m) => m.userId == userId);
        if (idx != -1) {
          _members[idx] = _members[idx].copyWith(
            status: PresenceStatus.present,
            lastVerifiedAt: DateTime.now(),
          );
        }
      } else {
        _verificationStatus = PresenceVerificationStatus.failed;
        _verificationError = 'Backend rejected presence proof.';
      }
    } else if (bleResult.failureReason == BleFailureReason.outOfRange) {
      _isBluetoothDeviceFound = true;
      _isBluetoothDeviceVerified = false;
      _lastDetectedRssi = bleResult.rssi;
      _verificationStatus = PresenceVerificationStatus.outOfRange;
      _verificationError = bleResult.message;
      _verificationStatusMessage = 'Organizer detected, but too far away. Move closer.';
    } else {
      _isBluetoothDeviceFound = false;
      _isBluetoothDeviceVerified = false;
      _verificationStatus = PresenceVerificationStatus.scanningForOrganizer;
      _verificationStatusMessage = 'Searching for organizer Bluetooth signal...';
    }

    notifyListeners();
  }

  void stopAutoPresenceScan() {
    _isAutoScanning = false;
    _autoScanPollTimer?.cancel();
    _autoScanPollTimer = null;
    _autoScanSub?.cancel();
    _autoScanSub = null;
  }

  /// Explicit universal presence verification via Bluetooth Low Energy.
  /// Validates Bluetooth hardware, permissions, signal discovery, RSSI proximity threshold, and backend proof.
  Future<bool> verifyPresence({
    required String userId,
    String method = 'ble',
  }) async {
    _verificationError = null;
    _isBluetoothDeviceFound = false;
    _isBluetoothDeviceVerified = false;
    _isPresenceRecorded = false;

    if (_activeSession == null) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'No active session selected.';
      _verificationStatusMessage = 'Presence was NOT verified.';
      notifyListeners();
      return false;
    }

    // 1. Group membership check
    final isEnrolled = _members.any((m) => m.userId == userId);
    if (!isEnrolled) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'Member is not enrolled in this group session. Presence verification cannot proceed.';
      _verificationStatusMessage = 'Presence was NOT verified.';
      _isPresenceRecorded = false;
      notifyListeners();
      return false;
    }

    // 2. Active Session & Check
    _verificationStatus = PresenceVerificationStatus.checkingPrerequisites;
    _verificationStatusMessage = 'Checking active group presence check...';
    notifyListeners();

    var check = _activeCheck;
    if (check == null || check.isExpired) {
      check = await _sessionService.getActivePresenceCheck(_activeSession!.id);
      _activeCheck = check;
    }

    if (check == null || check.isExpired) {
      _isPresenceSessionValid = false;
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'No active presence check in progress. Please wait for the organizer to start a check.';
      _verificationStatusMessage = 'Presence was NOT verified.';
      _isPresenceRecorded = false;
      notifyListeners();
      return false;
    }
    _isPresenceSessionValid = true;

    // 3. Bluetooth Hardware Availability Check
    final btAvailable = await _bleService.isBluetoothAvailable();
    _isBluetoothAvailable = btAvailable;
    if (!btAvailable) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'Bluetooth is turned off. Please turn on Bluetooth to verify presence.';
      _verificationStatusMessage = 'Presence was NOT verified.';
      _isPresenceRecorded = false;
      notifyListeners();
      return false;
    }

    // 4. Bluetooth Permission Check
    final permGranted = await _bleService.requestPermissions();
    _isBluetoothPermissionGranted = permGranted;
    if (!permGranted) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'Bluetooth permission denied. Bluetooth access is required to detect the group organizer device.';
      _verificationStatusMessage = 'Presence was NOT verified.';
      _isPresenceRecorded = false;
      notifyListeners();
      return false;
    }

    // 5. Bluetooth Device Scan & Proximity Threshold Verification
    int? detectedRssi;
    if (method == 'ble') {
      _verificationStatus = PresenceVerificationStatus.scanningForOrganizer;
      _verificationStatusMessage = 'Searching for organizer Bluetooth device...';
      notifyListeners();

      final requiredThreshold = _activeSession?.proximityThresholdRssi ?? AppConfig.defaultProximityRssi;
      final bleResult = await _bleService.scanAndVerifyPresenceDevice(
        expectedToken: check.checkToken,
        expectedSessionCode: _activeSession?.joinCode,
        proximityThresholdRssi: requiredThreshold,
        timeout: const Duration(seconds: 8),
      );

      if (!bleResult.isSuccess) {
        _isBluetoothDeviceFound = bleResult.failureReason == BleFailureReason.wrongDevice ||
            bleResult.failureReason == BleFailureReason.outOfRange;
        _isBluetoothDeviceVerified = false;
        _lastDetectedRssi = bleResult.rssi;
        _verificationStatus = bleResult.failureReason == BleFailureReason.outOfRange
            ? PresenceVerificationStatus.outOfRange
            : PresenceVerificationStatus.failed;
        _verificationError = bleResult.message;
        _verificationStatusMessage = 'Presence was NOT verified.';
        _isPresenceRecorded = false;
        notifyListeners();
        return false;
      }

      _isBluetoothDeviceFound = true;
      _isBluetoothDeviceVerified = true;
      detectedRssi = bleResult.rssi;
      _lastDetectedRssi = detectedRssi;
    }

    // 6. Backend Authorization and Presence Record Creation
    _verificationStatus = PresenceVerificationStatus.recordingPresence;
    _verificationStatusMessage = 'Recording presence with backend...';
    notifyListeners();

    final backendSuccess = await _sessionService.verifyMemberPresence(
      sessionId: _activeSession!.id,
      checkId: check.id,
      userId: userId,
      token: check.checkToken,
      method: method,
      rssi: detectedRssi,
    );

    if (!backendSuccess) {
      _verificationStatus = PresenceVerificationStatus.failed;
      _verificationError = 'Backend authorization rejected the presence verification request.';
      _verificationStatusMessage = 'Presence was NOT verified.';
      _isPresenceRecorded = false;
      notifyListeners();
      return false;
    }

    // 7. Successful Presence Recording
    _isPresenceRecorded = true;
    _verificationStatus = PresenceVerificationStatus.success;
    _verificationError = null;
    _verificationStatusMessage = '✓ Organizer detected\n✓ Bluetooth proximity verified\n\nYou are PRESENT';

    // Update local member cache
    final idx = _members.indexWhere((m) => m.userId == userId);
    if (idx != -1) {
      _members[idx] = _members[idx].copyWith(
        status: PresenceStatus.present,
        lastVerifiedAt: DateTime.now(),
      );
    }

    notifyListeners();
    return true;
  }

  /// Backward compatibility forwarding methods
  Future<bool> verifyAttendance({
    required String userId,
    String method = 'ble',
  }) =>
      verifyPresence(userId: userId, method: method);

  Future<bool> verifySelfPresence({
    required String userId,
    String method = 'ble',
  }) =>
      verifyPresence(userId: userId, method: method);

  /// Organizer manually confirms a member
  Future<void> manuallyConfirmMember(String userId) async {
    if (_activeSession == null) return;
    final idx = _members.indexWhere((m) => m.userId == userId);
    if (idx != -1) {
      _members[idx] = _members[idx].copyWith(
        status: PresenceStatus.manuallyConfirmed,
        lastVerifiedAt: DateTime.now(),
      );
      notifyListeners();
    }
    await _sessionService.updateMemberStatus(
      sessionId: _activeSession!.id,
      userId: userId,
      status: PresenceStatus.manuallyConfirmed,
    );
  }

  /// Organizer marks a member missing
  Future<void> markMemberMissing(String userId) async {
    if (_activeSession == null) return;
    final idx = _members.indexWhere((m) => m.userId == userId);
    if (idx != -1) {
      _members[idx] = _members[idx].copyWith(
        status: PresenceStatus.missing,
      );
      notifyListeners();
    }
    await _sessionService.updateMemberStatus(
      sessionId: _activeSession!.id,
      userId: userId,
      status: PresenceStatus.missing,
    );
  }

  /// Organizer marks a member possibly away
  Future<void> markMemberAway(String userId) async {
    if (_activeSession == null) return;
    final idx = _members.indexWhere((m) => m.userId == userId);
    if (idx != -1) {
      _members[idx] = _members[idx].copyWith(
        status: PresenceStatus.possiblyAway,
      );
      notifyListeners();
    }
    await _sessionService.updateMemberStatus(
      sessionId: _activeSession!.id,
      userId: userId,
      status: PresenceStatus.possiblyAway,
    );
  }

  /// Organizer ends the session
  Future<void> endSession() async {
    if (_activeSession == null) return;
    stopAutoPresenceScan();
    await stopOrganizerAdvertising();
    await _sessionService.endSession(_activeSession!.id);
    _activeSession = _activeSession!.copyWith(status: 'completed');
    _isCheckingPresence = false;
    notifyListeners();
  }

  /// Member leaves the active session
  Future<void> leaveSession(String userId) async {
    if (_activeSession == null) return;
    stopAutoPresenceScan();
    await stopOrganizerAdvertising();
    await _sessionService.leaveSession(
      sessionId: _activeSession!.id,
      userId: userId,
    );
    _activeSession = null;
    notifyListeners();
  }

  /// Export CSV string
  String exportCsv() {
    if (_activeSession == null) return '';
    return ReportService.generateCsv(
      session: _activeSession!,
      members: _members,
    );
  }

  /// Share executive summary to WhatsApp/SMS/Email
  Future<void> shareSummary() async {
    if (_activeSession == null) return;
    await ReportService.shareReport(
      session: _activeSession!,
      members: _members,
    );
  }

  @override
  void dispose() {
    stopAutoPresenceScan();
    stopOrganizerAdvertising(notify: false);
    _membersSub?.cancel();
    _eventsSub?.cancel();
    _bleSub?.cancel();
    _checkTimer?.cancel();
    _bleService.dispose();
    super.dispose();
  }
}
