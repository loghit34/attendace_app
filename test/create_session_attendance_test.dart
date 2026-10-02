import 'package:flutter_test/flutter_test.dart';
import 'package:herenow/core/models/session_member_model.dart';
import 'package:herenow/core/models/user_model.dart';
import 'package:herenow/core/state/session_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Create Session & Attendance Flow Tests', () {
    test('createSession creates session, sets organizer as present, and generates join code', () async {
      final provider = SessionProvider();
      final now = DateTime.now();

      final session = await provider.createSession(
        name: 'yug',
        organizerId: 'b0cdbbce-606d-4232-97e2-91c9dd99ce22',
        organizerName: 'lohit',
        description: 'ydid',
        startTime: now,
        endTime: now.add(const Duration(hours: 8)),
      );

      // Verify session creation
      expect(session, isNotNull);
      expect(session!.name, 'yug');
      expect(session.description, 'ydid');
      expect(session.joinCode.startsWith('HN-'), isTrue);
      expect(provider.activeSession?.id, session.id);

      // Verify live headcount and attendance
      expect(provider.totalCount, greaterThanOrEqualTo(1));
      expect(provider.presentCount, greaterThanOrEqualTo(1));
      expect(provider.members.any((m) => m.userId == 'b0cdbbce-606d-4232-97e2-91c9dd99ce22'), isTrue);
    });

    test('member joining and manual attendance status updates work seamlessly', () async {
      final provider = SessionProvider();
      final now = DateTime.now();

      final session = await provider.createSession(
        name: 'Office Attendance',
        organizerId: 'b0cdbbce-606d-4232-97e2-91c9dd99ce22',
        startTime: now,
        endTime: now.add(const Duration(hours: 8)),
      );

      expect(session, isNotNull);

      // Join a member
      final memberUser = UserModel(
        id: '2c76fe3d-2d47-4c56-993f-7fce723feaa0',
        name: 'ghosh',
        email: 'ghoshlo@gmail.com',
      );

      final joined = await provider.joinSessionByCode(
        joinCode: session!.joinCode,
        user: memberUser,
      );

      expect(joined, isTrue);

      // Verify member is in the list
      final member = provider.members.firstWhere((m) => m.userId == memberUser.id);
      expect(member.userName, 'ghosh');
      expect(member.status, PresenceStatus.missing);

      // Organizer manually confirms member attendance
      await provider.manuallyConfirmMember(memberUser.id);
      expect(provider.presentCount, 2);

      // Organizer marks member away
      await provider.markMemberAway(memberUser.id);
      expect(provider.possiblyAwayCount, 1);

      // Organizer marks member missing
      await provider.markMemberMissing(memberUser.id);
      expect(provider.missingCount, 1);

      // Member cannot self-verify without active organizer check
      final failedVerify = await provider.verifySelfPresence(userId: memberUser.id, method: 'manual');
      expect(failedVerify, isFalse);
      expect(provider.presentCount, 1);

      // Organizer starts active presence check pulse
      await provider.startPresenceCheck('b0cdbbce-606d-4232-97e2-91c9dd99ce22');

      // Member self verifies presence during active check
      final successVerify = await provider.verifySelfPresence(userId: memberUser.id, method: 'manual');
      expect(successVerify, isTrue);
      expect(provider.presentCount, 2);
    });
  });
}
