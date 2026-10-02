import 'package:flutter_test/flutter_test.dart';
import 'package:herenow/core/models/session_member_model.dart';
import 'package:herenow/core/models/session_model.dart';
import 'package:herenow/core/models/user_model.dart';
import 'package:herenow/core/services/anti_fraud_service.dart';
import 'package:herenow/core/services/location_service.dart';
import 'package:herenow/core/services/report_service.dart';
import 'fixtures/demo_session_service.dart';

void main() {
  group('AntiFraudService Tests', () {
    test('generatePresenceToken creates deterministic 16-char token', () {
      final now = DateTime(2026, 9, 29, 12, 0, 0);
      final token1 = AntiFraudService.generatePresenceToken(
        sessionId: 'sess-1',
        checkId: 'chk-1',
        timestamp: now,
      );
      final token2 = AntiFraudService.generatePresenceToken(
        sessionId: 'sess-1',
        checkId: 'chk-1',
        timestamp: now,
      );

      expect(token1.length, 16);
      expect(token1, equals(token2));
    });

    test('verifyProof succeeds for valid token within time window', () {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: 1));

      final result = AntiFraudService.verifyProof(
        sessionId: 'sess-test',
        checkId: 'chk-test-1',
        memberId: 'user-valid',
        receivedToken: 'VALID_TOKEN_123',
        checkExpiresAt: expiresAt,
        proofTimestamp: now,
      );

      expect(result.isValid, isTrue);
      expect(result.tokenHash, isNotNull);
    });

    test('verifyProof rejects expired check window', () {
      final now = DateTime.now();
      final expiredAt = now.subtract(const Duration(minutes: 5));

      final result = AntiFraudService.verifyProof(
        sessionId: 'sess-test',
        checkId: 'chk-test-expired',
        memberId: 'user-expired',
        receivedToken: 'TOKEN_123',
        checkExpiresAt: expiredAt,
        proofTimestamp: now,
      );

      expect(result.isValid, isFalse);
      expect(result.failureReason, contains('expired'));
    });

    test('verifyProof prevents replay attack with identical signature', () {
      final now = DateTime.now();
      final expiresAt = now.add(const Duration(minutes: 2));

      final res1 = AntiFraudService.verifyProof(
        sessionId: 'sess-replay',
        checkId: 'chk-replay-1',
        memberId: 'user-replay-test',
        receivedToken: 'ROTATING_TOKEN_A',
        checkExpiresAt: expiresAt,
        proofTimestamp: now,
      );
      expect(res1.isValid, isTrue);

      // Attempt replay
      final res2 = AntiFraudService.verifyProof(
        sessionId: 'sess-replay',
        checkId: 'chk-replay-1',
        memberId: 'user-replay-test',
        receivedToken: 'ROTATING_TOKEN_A',
        checkExpiresAt: expiresAt,
        proofTimestamp: now,
      );
      expect(res2.isValid, isFalse);
      expect(res2.failureReason, contains('Replay attack prevented'));
    });
  });

  group('LocationService Geofence Tests', () {
    test('accurately calculates Haversine distance and geofence boundary', () {
      // Meeting Point: Digha Sea Beach (21.6266, 87.5074)
      const meetingLat = 21.6266;
      const meetingLon = 87.5074;

      // Nearby User (~30m away)
      const nearLat = 21.6268;
      const nearLon = 87.5074;
      final nearResult = LocationService.verifyGeofence(
        userLat: nearLat,
        userLon: nearLon,
        meetingLat: meetingLat,
        meetingLon: meetingLon,
        geofenceRadiusMeters: 100.0,
      );
      expect(nearResult.isWithinGeofence, isTrue);

      // Far away User (~5km away)
      const farLat = 21.6700;
      const farLon = 87.5074;
      final farResult = LocationService.verifyGeofence(
        userLat: farLat,
        userLon: farLon,
        meetingLat: meetingLat,
        meetingLon: meetingLon,
        geofenceRadiusMeters: 100.0,
      );
      expect(farResult.isWithinGeofence, isFalse);
    });
  });

  group('SessionService & Demo Provider Tests', () {
    late DemoSessionService service;

    setUp(() {
      service = DemoSessionService();
    });

    test('seeded session contains 30 members with 28 present and 2 missing', () async {
      final members = await service.getSessionMembers('session-digha-001');
      expect(members.length, equals(30));

      final present = members.where((m) => m.status == PresenceStatus.present).length;
      final missing = members.where((m) => m.status == PresenceStatus.missing).length;

      expect(present, equals(28));
      expect(missing, equals(2));

      final rohan = members.firstWhere((m) => m.userName.contains('Rohan'));
      final arjun = members.firstWhere((m) => m.userName.contains('Arjun'));
      expect(rohan.status, equals(PresenceStatus.missing));
      expect(arjun.status, equals(PresenceStatus.missing));
    });

    test('manually confirming missing member updates status to manuallyConfirmed', () async {
      final membersBefore = await service.getSessionMembers('session-digha-001');
      final rohan = membersBefore.firstWhere((m) => m.userName.contains('Rohan'));

      await service.updateMemberStatus(
        sessionId: 'session-digha-001',
        userId: rohan.userId,
        status: PresenceStatus.manuallyConfirmed,
      );

      final membersAfter = await service.getSessionMembers('session-digha-001');
      final rohanAfter = membersAfter.firstWhere((m) => m.userId == rohan.userId);

      expect(rohanAfter.status, equals(PresenceStatus.manuallyConfirmed));
      expect(rohanAfter.lastVerifiedAt, isNotNull);
    });

    test('joining with code HN-482731 succeeds', () async {
      final session = await service.getSessionByCode('HN-482731');
      expect(session, isNotNull);
      expect(session!.name, equals('Company Trip — Digha'));

      final newUser = UserModel(id: 'usr-new-99', name: 'Kabir Khan');
      final member = await service.joinSession(
        sessionId: session.id,
        user: newUser,
      );

      expect(member.userName, equals('Kabir Khan'));
      expect(member.status, equals(PresenceStatus.missing));
    });
  });

  group('ReportService Tests', () {
    test('generateCsv produces valid tabular format', () {
      final session = SessionModel(
        id: 's-1',
        organizerId: 'u-1',
        name: 'Sports Team — Stadium',
        joinCode: 'HN-998877',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 4)),
      );

      final members = [
        SessionMemberModel(
          id: 'm-1',
          sessionId: 's-1',
          userId: 'u-1',
          userName: 'Coach John',
          role: 'organizer',
          status: PresenceStatus.present,
          lastVerifiedAt: DateTime.now(),
        ),
        SessionMemberModel(
          id: 'm-2',
          sessionId: 's-1',
          userId: 'u-2',
          userName: 'Striker Leo',
          role: 'member',
          status: PresenceStatus.missing,
        ),
      ];

      final csv = ReportService.generateCsv(session: session, members: members);
      expect(csv, contains('HereNow Presence Verification Report'));
      expect(csv, contains('Sports Team — Stadium'));
      expect(csv, contains('Coach John'));
      expect(csv, contains('Striker Leo'));
      expect(csv, contains('Present'));
      expect(csv, contains('Missing'));
    });

    test('generateSummaryText produces formatted executive report', () {
      final session = SessionModel(
        id: 's-1',
        organizerId: 'u-1',
        name: 'Field Team Alpha',
        joinCode: 'HN-112233',
        startTime: DateTime.now(),
        endTime: DateTime.now().add(const Duration(hours: 2)),
      );

      final members = [
        SessionMemberModel(
          id: 'm-1',
          sessionId: 's-1',
          userId: 'u-1',
          userName: 'Supervisor',
          status: PresenceStatus.present,
        ),
      ];

      final summary = ReportService.generateSummaryText(session: session, members: members);
      expect(summary, contains('HereNow Presence Report'));
      expect(summary, contains('1 / 1 Present'));
      expect(summary, contains('🟢 Present: 1'));
    });
  });
}
