import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herenow/core/config/app_config.dart';
import 'package:herenow/core/models/session_member_model.dart';
import 'package:herenow/core/models/session_model.dart';
import 'package:herenow/core/models/user_model.dart';
import 'package:herenow/core/services/ble_service.dart';
import 'package:herenow/core/state/auth_provider.dart';
import 'package:herenow/core/state/session_provider.dart';
import 'package:herenow/core/utils/join_code_helper.dart';
import 'package:herenow/ui/screens/organizer/organizer_dashboard_screen.dart';
import 'package:provider/provider.dart';

import 'fixtures/demo_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DemoSessionService sessionService;
  late SessionProvider provider;

  const organizerId = 'organizer-test-user-01';
  const memberId = 'member-test-user-02';

  final memberUser = UserModel(
    id: memberId,
    name: 'Test Member',
    email: 'member@test.com',
  );

  setUp(() {
    BleService.resetTestOverrides();
    sessionService = DemoSessionService();
    provider = SessionProvider(sessionService: sessionService);
  });

  tearDown(() {
    provider.clearSessionState();
    BleService.resetTestOverrides();
  });

  group('Join Code Normalization Tests (JoinCodeHelper)', () {
    test('Standard join code formats are normalized cleanly to HN-100249', () {
      expect(JoinCodeHelper.normalize('HN-100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('hn-100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('  HN-100249  '), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('HN 100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('HN100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('https://herenow.app/join/HN-100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('https://herenow.app/join/100249'), equals('HN-100249'));
      expect(JoinCodeHelper.normalize('https://herenow.app/join/HN-100249?ref=qr'), equals('HN-100249'));
    });

    test('Custom alphanumeric codes are preserved', () {
      expect(JoinCodeHelper.normalize('EVENT-2026'), equals('EVENT-2026'));
      expect(JoinCodeHelper.normalize('  conf-nyc  '), equals('CONF-NYC'));
    });

    test('Empty or blank input returns empty string', () {
      expect(JoinCodeHelper.normalize(''), equals(''));
      expect(JoinCodeHelper.normalize('   '), equals(''));
    });
  });

  group('End-to-End Session Join & Presence State Separation with HN-100249', () {
    test('Exact flow: Organizer creates HN-100249 -> Member joins with HN-100249 -> Status JOINED (missing) -> BLE verified -> Status PRESENT', () async {
      final now = DateTime.now();

      // 1. Organizer creates session with exact code HN-100249
      final created = await sessionService.createSession(
        SessionModel(
          id: 'session-hn-100249-id',
          organizerId: organizerId,
          name: 'Team Standup',
          joinCode: 'HN-100249',
          startTime: now,
          endTime: now.add(const Duration(hours: 2)),
          status: 'active',
        ),
      );

      expect(created.joinCode, equals('HN-100249'));

      // 2. Member enters HN-100249 (or variations like lowercase or without hyphen)
      final joinedWithExact = await provider.joinSessionByCode(
        joinCode: 'HN-100249',
        user: memberUser,
      );

      expect(joinedWithExact, isTrue);
      expect(provider.activeSession, isNotNull);
      expect(provider.activeSession!.joinCode, equals('HN-100249'));

      // 3. INVARIANT CHECK: Joining ONLY grants enrollment. Member is NOT yet marked present.
      expect(provider.isMemberEnrolled(memberId), isTrue);
      expect(provider.isBluetoothDeviceVerified, isFalse);
      expect(provider.isPresenceRecorded, isFalse);

      final memberRecordAfterJoin = provider.members.firstWhere((m) => m.userId == memberId);
      expect(memberRecordAfterJoin.status, equals(PresenceStatus.missing));
      expect(memberRecordAfterJoin.lastVerifiedAt, isNull);

      // 4. Organizer initiates presence check pulse
      await provider.startPresenceCheck(organizerId);
      final check = provider.activeCheck!;
      expect(check.checkToken, isNotEmpty);

      // 5. Member device scans and detects Organizer BLE signal within proximity threshold
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'ble-beacon-organizer-01',
          deviceName: 'HN_${check.checkToken}',
          rssi: -58,
          discoveredToken: check.checkToken,
        )
      ];

      // 6. Proximity verification completes -> Member status becomes PRESENT
      final verified = await provider.verifyPresence(userId: memberId);
      expect(verified, isTrue);
      expect(provider.isPresenceRecorded, isTrue);
      expect(provider.isBluetoothDeviceVerified, isTrue);

      final memberRecordAfterBle = provider.members.firstWhere((m) => m.userId == memberId);
      expect(memberRecordAfterBle.status, equals(PresenceStatus.present));
      expect(memberRecordAfterBle.lastVerifiedAt, isNotNull);
    });

    test('Member entering lowercase "hn-100249" finds the exact session', () async {
      final now = DateTime.now();
      await sessionService.createSession(
        SessionModel(
          id: 'session-hn-lowercase-id',
          organizerId: organizerId,
          name: 'Trip Meeting',
          joinCode: 'HN-100249',
          startTime: now,
          endTime: now.add(const Duration(hours: 2)),
          status: 'active',
        ),
      );

      final joined = await provider.joinSessionByCode(
        joinCode: 'hn-100249',
        user: memberUser,
      );

      expect(joined, isTrue);
      expect(provider.activeSession?.id, equals('session-hn-lowercase-id'));
    });

    test('Member entering 6-digit number "100249" finds the exact session', () async {
      final now = DateTime.now();
      await sessionService.createSession(
        SessionModel(
          id: 'session-hn-digits-id',
          organizerId: organizerId,
          name: 'Trip Meeting',
          joinCode: 'HN-100249',
          startTime: now,
          endTime: now.add(const Duration(hours: 2)),
          status: 'active',
        ),
      );

      final joined = await provider.joinSessionByCode(
        joinCode: '100249',
        user: memberUser,
      );

      expect(joined, isTrue);
      expect(provider.activeSession?.id, equals('session-hn-digits-id'));
    });

    test('Member scanning QR invite link "https://herenow.app/join/HN-100249" finds session', () async {
      final now = DateTime.now();
      await sessionService.createSession(
        SessionModel(
          id: 'session-hn-qr-id',
          organizerId: organizerId,
          name: 'Conference Room A',
          joinCode: 'HN-100249',
          startTime: now,
          endTime: now.add(const Duration(hours: 2)),
          status: 'active',
        ),
      );

      final joined = await provider.joinSessionByCode(
        joinCode: 'https://herenow.app/join/HN-100249',
        user: memberUser,
      );

      expect(joined, isTrue);
      expect(provider.activeSession?.id, equals('session-hn-qr-id'));
    });

    test('Invalid code returns "Session not found. Please check your join code."', () async {
      final joined = await provider.joinSessionByCode(
        joinCode: 'HN-999999',
        user: memberUser,
      );

      expect(joined, isFalse);
      expect(provider.errorMessage, equals('Session not found. Please check your join code.'));
    });

    test('Expired session returns "This session has already expired."', () async {
      final past = DateTime.now().subtract(const Duration(hours: 4));
      await sessionService.createSession(
        SessionModel(
          id: 'session-expired-id',
          organizerId: organizerId,
          name: 'Yesterday Meeting',
          joinCode: 'HN-100249',
          startTime: past.subtract(const Duration(hours: 1)),
          endTime: past,
          status: 'active',
        ),
      );

      final joined = await provider.joinSessionByCode(
        joinCode: 'HN-100249',
        user: memberUser,
      );

      expect(joined, isFalse);
      expect(provider.errorMessage, equals('This session has already expired.'));
    });
  });

  group('OrganizerDashboardScreen UI Layout & Overflow Tests', () {
    testWidgets('renders OrganizerDashboardScreen on narrow mobile width without any RenderFlex overflow', (WidgetTester tester) async {
      // Simulate standard narrow Android phone width (360x780, matching screenshot)
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final session = await sessionService.createSession(
        SessionModel(
          id: 'session-gkh-overflow-test',
          organizerId: organizerId,
          name: 'gkh',
          joinCode: 'HN-100721',
          startTime: now,
          endTime: now.add(const Duration(hours: 4)),
          status: 'active',
        ),
      );

      await provider.selectSession(session.id);

      final authProvider = AuthProvider();
      authProvider.setMockUser(UserModel(
        id: organizerId,
        name: 'Organizer (You)',
        email: 'organizer@test.com',
      ));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SessionProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: OrganizerDashboardScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check header and member list renders cleanly
      expect(find.text('gkh'), findsOneWidget);
      expect(find.textContaining('HN-100721'), findsOneWidget);
      expect(find.text('Tap for actions'), findsOneWidget);
      expect(find.textContaining('Organizer'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
