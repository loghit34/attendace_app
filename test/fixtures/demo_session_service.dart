import 'dart:async';
import 'package:herenow/core/config/app_config.dart';
import 'package:herenow/core/models/presence_check_model.dart';
import 'package:herenow/core/models/presence_event_model.dart';
import 'package:herenow/core/models/session_member_model.dart';
import 'package:herenow/core/models/session_model.dart';
import 'package:herenow/core/models/user_model.dart';
import 'package:herenow/core/services/anti_fraud_service.dart';
import 'package:herenow/core/services/session_service.dart';
import 'package:herenow/core/utils/join_code_helper.dart';
import 'package:uuid/uuid.dart';

/// Test fixture: in-memory simulated session service for testing only.
class DemoSessionService implements SessionService {
  final Map<String, SessionModel> _sessions = {};
  final Map<String, List<SessionMemberModel>> _members = {};
  final Map<String, List<PresenceEventModel>> _events = {};
  final Map<String, PresenceCheckModel> _checks = {};

  final StreamController<List<SessionMemberModel>> _membersStreamController =
      StreamController<List<SessionMemberModel>>.broadcast();
  final StreamController<PresenceEventModel> _eventsStreamController =
      StreamController<PresenceEventModel>.broadcast();

  DemoSessionService() {
    _seedDefaultTripData();
  }

  void _seedDefaultTripData() {
    const sessionId = 'session-digha-001';
    const orgId = 'user-organizer-01';

    final session = SessionModel(
      id: sessionId,
      organizerId: orgId,
      name: 'Company Trip — Digha',
      description: 'Annual corporate seaside retreat. Headcount before departure.',
      category: 'COMPANY',
      joinCode: 'HN-482731',
      startTime: DateTime.now().subtract(const Duration(hours: 2)),
      endTime: DateTime.now().add(const Duration(hours: 6)),
      proximityMode: ProximityMode.normal,
      meetingLatitude: 21.6266,
      meetingLongitude: 87.5074,
      geofenceRadius: 100.0,
      status: 'active',
    );
    _sessions[sessionId] = session;

    final List<SessionMemberModel> seededMembers = [];

    final initialNames = [
      'Rahul Sharma', 'Amit Verma', 'Priya Patel', 'Sneha Roy', 'Vikram Das',
      'Ananya Sen', 'Karan Mehra', 'Deepak Joshi', 'Neha Gupta', 'Siddharth Rao',
      'Pooja Nair', 'Ravi Shankar', 'Kavita Das', 'Manish Kapoor', 'Sunita Reddy',
      'Aditya Bose', 'Swati Mishra', 'Tarun Jain', 'Meera Iyer', 'Nikhil Chawla',
      'Bhavna Saxena', 'Kunal Ghosh', 'Ritu Aggarwal', 'Vivek Dubey', 'Tanvi Singhal',
      'Harish Menon', 'Shruti Paul', 'Gaurav Kulkarni', 'Rohan Mehta', 'Arjun Kapoor'
    ];

    for (int i = 0; i < initialNames.length; i++) {
      final name = initialNames[i];
      final isRohanOrArjun = name.startsWith('Rohan') || name.startsWith('Arjun');
      final isOrg = i == 0;

      seededMembers.add(
        SessionMemberModel(
          id: 'mem-$i',
          sessionId: sessionId,
          userId: isOrg ? orgId : 'user-$i',
          userName: name,
          userPhone: '+91 98765 ${10000 + i}',
          role: isOrg ? 'organizer' : 'member',
          status: isRohanOrArjun ? PresenceStatus.missing : PresenceStatus.present,
          lastVerifiedAt: isRohanOrArjun
              ? null
              : DateTime.now().subtract(Duration(seconds: 20 + (i * 3))),
          joinedAt: DateTime.now().subtract(Duration(minutes: 60 - i)),
        ),
      );
    }

    _members[sessionId] = seededMembers;
    _events[sessionId] = [
      PresenceEventModel(
        id: 'ev-1',
        sessionId: sessionId,
        eventType: 'check_started',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      PresenceEventModel(
        id: 'ev-2',
        sessionId: sessionId,
        userName: 'Rahul Sharma',
        eventType: 'verified_ble',
        createdAt: DateTime.now().subtract(const Duration(seconds: 45)),
      ),
      PresenceEventModel(
        id: 'ev-3',
        sessionId: sessionId,
        userName: 'Amit Verma',
        eventType: 'verified_ble',
        createdAt: DateTime.now().subtract(const Duration(seconds: 35)),
      ),
    ];
  }

  @override
  Future<SessionModel> createSession(SessionModel session) async {
    _sessions[session.id] = session;
    _members[session.id] = [
      SessionMemberModel(
        id: 'mem-${const Uuid().v4()}',
        sessionId: session.id,
        userId: session.organizerId,
        userName: 'You (Organizer)',
        role: 'organizer',
        status: PresenceStatus.present,
        lastVerifiedAt: DateTime.now(),
      )
    ];
    _events[session.id] = [
      PresenceEventModel(
        id: const Uuid().v4(),
        sessionId: session.id,
        eventType: 'created_session',
      )
    ];
    return session;
  }

  @override
  Future<SessionModel?> getSession(String sessionId) async {
    return _sessions[sessionId];
  }

  @override
  Future<SessionModel?> getSessionByCode(String joinCode) async {
    final normalized = JoinCodeHelper.normalize(joinCode);
    for (final s in _sessions.values) {
      if (JoinCodeHelper.normalize(s.joinCode) == normalized || s.id == joinCode.trim()) {
        return s;
      }
    }
    return null;
  }

  @override
  Future<List<SessionModel>> getUserSessions(String userId) async {
    return _sessions.values.toList();
  }

  @override
  Future<SessionMemberModel> joinSession({
    required String sessionId,
    required UserModel user,
    String role = 'member',
  }) async {
    final list = _members.putIfAbsent(sessionId, () => []);
    final existingIndex = list.indexWhere((m) => m.userId == user.id);

    final member = SessionMemberModel(
      id: const Uuid().v4(),
      sessionId: sessionId,
      userId: user.id,
      userName: user.name,
      userPhone: user.phone,
      userEmail: user.email,
      role: role,
      status: PresenceStatus.missing,
      joinedAt: DateTime.now(),
    );

    if (existingIndex >= 0) {
      list[existingIndex] = member;
    } else {
      list.add(member);
    }

    _logDemoEvent(sessionId: sessionId, userName: user.name, eventType: 'joined');
    _notifyMembers(sessionId);
    return member;
  }

  @override
  Future<List<SessionMemberModel>> getSessionMembers(String sessionId) async {
    return List.from(_members[sessionId] ?? []);
  }

  @override
  Stream<List<SessionMemberModel>> streamSessionMembers(String sessionId) {
    return _membersStreamController.stream.where((list) {
      return list.isNotEmpty && list.first.sessionId == sessionId;
    });
  }

  @override
  Future<PresenceCheckModel> startPresenceCheck({
    required String sessionId,
    required String organizerId,
  }) async {
    final checkId = const Uuid().v4();
    final now = DateTime.now();
    final expiresAt = now.add(AppConfig.checkTokenDuration);
    final token = AntiFraudService.generatePresenceToken(
      sessionId: sessionId,
      checkId: checkId,
      timestamp: now,
    );

    final check = PresenceCheckModel(
      id: checkId,
      sessionId: sessionId,
      initiatorId: organizerId,
      checkToken: token,
      startedAt: now,
      expiresAt: expiresAt,
    );
    _checks[sessionId] = check;

    _logDemoEvent(
      sessionId: sessionId,
      eventType: 'check_started',
    );

    return check;
  }

  @override
  Future<PresenceCheckModel?> getActivePresenceCheck(String sessionId) async {
    final check = _checks[sessionId];
    if (check != null && !check.isExpired && check.status == 'active') {
      return check;
    }
    return null;
  }

  @override
  Future<bool> verifyMemberPresence({
    required String sessionId,
    required String checkId,
    required String userId,
    required String token,
    String method = 'ble',
    int? rssi,
  }) async {
    // 1. Enrollment check
    final list = _members[sessionId];
    if (list == null) return false;

    final index = list.indexWhere((m) => m.userId == userId);
    if (index < 0) return false;

    // If member is already verified as present, duplicate BLE detections are idempotent
    final existingMember = list[index];
    if (existingMember.status == PresenceStatus.present) {
      list[index] = existingMember.copyWith(lastVerifiedAt: DateTime.now());
      return true;
    }

    // 2. Active check validation
    final check = _checks[sessionId];
    if (check == null || check.id != checkId || check.isExpired) {
      return false;
    }

    // 3. Token match validation
    if (check.checkToken != token && !token.contains(check.checkToken)) {
      return false;
    }

    // 4. Anti-fraud server-side validation
    final verification = AntiFraudService.verifyProof(
      sessionId: sessionId,
      checkId: checkId,
      memberId: userId,
      receivedToken: token,
      checkExpiresAt: check.expiresAt,
      proofTimestamp: DateTime.now(),
    );

    if (!verification.isValid) {
      return false;
    }

    final existing = list[index];
    list[index] = existing.copyWith(
      status: PresenceStatus.present,
      lastVerifiedAt: DateTime.now(),
    );

    _logDemoEvent(
      sessionId: sessionId,
      userName: existing.userName,
      eventType: 'verified_ble',
      metadata: {'rssi': rssi ?? -60},
    );

    _notifyMembers(sessionId);
    return true;
  }

  @override
  Future<void> updateMemberStatus({
    required String sessionId,
    required String userId,
    required PresenceStatus status,
  }) async {
    final list = _members[sessionId];
    if (list == null) return;

    final index = list.indexWhere((m) => m.userId == userId);
    if (index < 0) return;

    final existing = list[index];
    list[index] = existing.copyWith(
      status: status,
      lastVerifiedAt: (status == PresenceStatus.present ||
              status == PresenceStatus.manuallyConfirmed)
          ? DateTime.now()
          : existing.lastVerifiedAt,
    );

    _logDemoEvent(
      sessionId: sessionId,
      userName: existing.userName,
      eventType: status == PresenceStatus.manuallyConfirmed
          ? 'manually_confirmed'
          : status == PresenceStatus.missing
              ? 'marked_missing'
              : 'status_updated',
    );

    _notifyMembers(sessionId);
  }

  @override
  Future<void> endSession(String sessionId) async {
    final s = _sessions[sessionId];
    if (s != null) {
      _sessions[sessionId] = s.copyWith(status: 'completed');
      _logDemoEvent(sessionId: sessionId, eventType: 'session_ended');
    }
  }

  @override
  Future<void> leaveSession({
    required String sessionId,
    required String userId,
  }) async {
    await updateMemberStatus(
      sessionId: sessionId,
      userId: userId,
      status: PresenceStatus.left,
    );
  }

  @override
  Future<List<PresenceEventModel>> getSessionEvents(String sessionId) async {
    return List.from((_events[sessionId] ?? []).reversed);
  }

  @override
  Stream<PresenceEventModel> streamSessionEvents(String sessionId) {
    return _eventsStreamController.stream.where((e) => e.sessionId == sessionId);
  }

  void _notifyMembers(String sessionId) {
    if (_members.containsKey(sessionId)) {
      _membersStreamController.add(List.from(_members[sessionId]!));
    }
  }

  void _logDemoEvent({
    required String sessionId,
    String? userName,
    required String eventType,
    Map<String, dynamic> metadata = const {},
  }) {
    final event = PresenceEventModel(
      id: const Uuid().v4(),
      sessionId: sessionId,
      userName: userName,
      eventType: eventType,
      createdAt: DateTime.now(),
      metadata: metadata,
    );
    _events.putIfAbsent(sessionId, () => []).add(event);
    _eventsStreamController.add(event);
  }
}
