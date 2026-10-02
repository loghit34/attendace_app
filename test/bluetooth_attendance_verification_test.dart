import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:herenow/core/config/app_config.dart';
import 'package:herenow/core/models/session_member_model.dart';
import 'package:herenow/core/models/user_model.dart';
import 'package:herenow/core/services/anti_fraud_service.dart';
import 'package:herenow/core/services/ble_service.dart';
import 'package:herenow/core/state/auth_provider.dart';
import 'package:herenow/core/state/session_provider.dart';
import 'package:herenow/ui/screens/member/member_presence_screen.dart';
import 'package:provider/provider.dart';

import 'fixtures/demo_session_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DemoSessionService sessionService;
  late SessionProvider provider;

  const organizerId = 'organizer-uuid-01';
  const enrolledMemberId = 'member-enrolled-02';
  const unenrolledMemberId = 'member-unenrolled-99';

  final memberUser = UserModel(
    id: enrolledMemberId,
    name: 'Alice Cooper',
    email: 'alice@company.com',
  );

  setUp(() async {
    BleService.resetTestOverrides();
    AntiFraudService.resetForTesting();
    sessionService = DemoSessionService();
    provider = SessionProvider(sessionService: sessionService);

    // Create active universal group session (Company Standup)
    final now = DateTime.now();
    final session = await provider.createSession(
      name: 'Engineering Sprint Sync',
      organizerId: organizerId,
      organizerName: 'Team Lead Sarah',
      category: 'COMPANY',
      proximityMode: ProximityMode.normal,
      startTime: now,
      endTime: now.add(const Duration(hours: 2)),
    );

    // Enroll member into the group session (Status is initialized to 'missing' / unverified)
    await sessionService.joinSession(
      sessionId: session!.id,
      user: memberUser,
    );

    // Reload members in provider
    await provider.selectSession(session.id);
  });

  tearDown(() {
    provider.clearSessionState();
    BleService.resetTestOverrides();
    AntiFraudService.resetForTesting();
  });

  group('Universal Bluetooth Proximity Presence Verification - Core Cases', () {
    test('Case 1: Enrolled + BLE device within proximity threshold -> presence succeeds', () async {
      // 1. Organizer starts active presence check
      await provider.startPresenceCheck(organizerId);
      final activeCheck = provider.activeCheck!;
      expect(activeCheck.checkToken, isNotEmpty);

      // 2. Setup environment: BT ON, Permission Granted, Organizer Beacon detected with RSSI -55 (well within normal threshold -75)
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'ble-beacon-organizer-01',
          deviceName: 'HN_${activeCheck.checkToken}',
          rssi: -55,
          discoveredToken: activeCheck.checkToken,
        )
      ];

      // 3. Member performs Bluetooth proximity verification
      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isTrue);
      expect(provider.isPresenceRecorded, isTrue);
      expect(provider.isBluetoothDeviceVerified, isTrue);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.success));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.present));
      expect(member.lastVerifiedAt, isNotNull);
    });

    test('Case 2: Enrolled + Bluetooth OFF -> presence verification fails', () async {
      await provider.startPresenceCheck(organizerId);

      // Bluetooth is powered off
      BleService.testBluetoothAvailable = false;
      BleService.testPermissionGranted = true;

      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.isBluetoothAvailable, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.failed));
      expect(provider.verificationError, contains('Bluetooth is turned off'));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 3: Enrolled + Bluetooth permission denied -> presence fails', () async {
      await provider.startPresenceCheck(organizerId);

      // Bluetooth is ON, but permission is denied by user
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = false;

      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.isBluetoothPermissionGranted, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.failed));
      expect(provider.verificationError, contains('permission denied'));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 4: Enrolled + wrong Bluetooth device -> presence fails', () async {
      await provider.startPresenceCheck(organizerId);

      // Wrong Bluetooth device detected (e.g. nearby headphones)
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'other-device-mac',
          deviceName: 'Bluetooth Headphones',
          rssi: -40,
          discoveredToken: 'WRONG_TOKEN_9999',
        )
      ];

      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.isBluetoothDeviceVerified, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.failed));
      expect(provider.verificationError, contains('Wrong Bluetooth device detected'));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 5: Enrolled + BLE signal too weak (out of proximity threshold) -> rejected as outOfRange', () async {
      await provider.startPresenceCheck(organizerId);
      final activeCheck = provider.activeCheck!;

      // Signal is -92 dBm (weaker than required normal threshold -75 dBm)
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'ble-beacon-organizer-01',
          deviceName: 'HN_${activeCheck.checkToken}',
          rssi: -92,
          discoveredToken: activeCheck.checkToken,
        )
      ];

      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.isBluetoothDeviceVerified, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.outOfRange));
      expect(provider.verificationError, contains('signal is too weak'));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 6: Enrolled + no Bluetooth device nearby -> presence fails', () async {
      await provider.startPresenceCheck(organizerId);

      // Zero Bluetooth devices detected
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [];

      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.isBluetoothDeviceFound, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.failed));
      expect(provider.verificationError, contains('No group session organizer device found'));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 7: Enrolled + Bluetooth verification timeout -> presence fails', () async {
      await provider.startPresenceCheck(organizerId);

      // Force timeout
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testForceTimeout = true;

      final success = await provider.verifyPresence(userId: enrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.failed));
      expect(provider.verificationError, contains('timed out'));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 8: Not enrolled + Bluetooth device present -> presence rejected', () async {
      await provider.startPresenceCheck(organizerId);
      final activeCheck = provider.activeCheck!;

      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'ble-beacon-organizer-01',
          deviceName: 'HN_${activeCheck.checkToken}',
          rssi: -55,
          discoveredToken: activeCheck.checkToken,
        )
      ];

      // Unenrolled member tries to verify presence
      final success = await provider.verifyPresence(userId: unenrolledMemberId);

      expect(success, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.failed));
      expect(provider.verificationError, contains('not enrolled'));
    });

    test('Case 9: User joins group but does not enter Bluetooth proximity -> remains unverified', () async {
      final newMember = UserModel(
        id: 'new-member-joining-now',
        name: 'Bob Newbie',
      );

      // Member joins via join code
      final joined = await provider.joinSessionByCode(
        joinCode: provider.activeSession!.joinCode,
        user: newMember,
      );

      expect(joined, isTrue);

      // Member is enrolled in the group
      expect(provider.isMemberEnrolled('new-member-joining-now'), isTrue);

      // Check member status immediately after joining (MUST be missing / unverified)
      final member = provider.members.firstWhere((m) => m.userId == 'new-member-joining-now');
      expect(member.status, equals(PresenceStatus.missing));
      expect(member.lastVerifiedAt, isNull);
    });

    test('Case 10: Attempt to call presence verification API directly with fake token or expired check -> backend rejects', () async {
      // 1. Direct call with non-existent check ID
      final fakeCheckResult = await sessionService.verifyMemberPresence(
        sessionId: provider.activeSession!.id,
        checkId: 'fake-nonexistent-check-id',
        userId: enrolledMemberId,
        token: 'MALICIOUS_TOKEN_ATTEMPT',
      );
      expect(fakeCheckResult, isFalse);

      // 2. Organizer creates a check
      await provider.startPresenceCheck(organizerId);
      final activeCheck = provider.activeCheck!;

      // 3. Direct call with invalid/spoofed token
      final wrongTokenResult = await sessionService.verifyMemberPresence(
        sessionId: provider.activeSession!.id,
        checkId: activeCheck.id,
        userId: enrolledMemberId,
        token: 'SPOOFED_UNAUTHORIZED_TOKEN',
      );
      expect(wrongTokenResult, isFalse);

      // 4. Direct call for an unenrolled member
      final unenrolledResult = await sessionService.verifyMemberPresence(
        sessionId: provider.activeSession!.id,
        checkId: activeCheck.id,
        userId: 'completely-unenrolled-user-id',
        token: activeCheck.checkToken,
      );
      expect(unenrolledResult, isFalse);

      // Ensure member presence in backend is still unverified (missing)
      final members = await sessionService.getSessionMembers(provider.activeSession!.id);
      final member = members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });

    test('Case 11: Duplicate BLE detections do NOT create duplicate presence records or crash', () async {
      await provider.startPresenceCheck(organizerId);
      final activeCheck = provider.activeCheck!;

      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'ble-beacon-organizer-01',
          deviceName: 'HN_${activeCheck.checkToken}',
          rssi: -55,
          discoveredToken: activeCheck.checkToken,
        )
      ];

      // 1st verification
      final firstOk = await provider.verifyPresence(userId: enrolledMemberId);
      expect(firstOk, isTrue);

      // 2nd repeated detection (same check)
      final secondOk = await provider.verifyPresence(userId: enrolledMemberId);
      expect(secondOk, isTrue);

      final members = await sessionService.getSessionMembers(provider.activeSession!.id);
      final matching = members.where((m) => m.userId == enrolledMemberId).toList();
      expect(matching.length, equals(1)); // exactly 1 member record
      expect(matching.first.status, equals(PresenceStatus.present));
    });
  });

  group('Universal Group Types Verification', () {
    test('Works seamlessly for Travel and Event groups', () async {
      final now = DateTime.now();
      final travelSession = await provider.createSession(
        name: 'Kolkata to Darjeeling Tour',
        organizerId: organizerId,
        category: 'TRAVEL',
        proximityMode: ProximityMode.wide,
        startTime: now,
        endTime: now.add(const Duration(hours: 4)),
      );

      expect(travelSession, isNotNull);
      expect(travelSession!.groupType, equals(GroupType.travel));
      expect(travelSession.proximityMode, equals(ProximityMode.wide));
      expect(travelSession.proximityThresholdRssi, equals(-85));
    });
  });

  group('State Separation Invariants', () {
    test('enrolled does NOT equal bluetooth_device_verified or presence_recorded', () {
      final isEnrolled = provider.isMemberEnrolled(enrolledMemberId);
      final isBluetoothVerified = provider.isBluetoothDeviceVerified;
      final isPresenceRecorded = provider.isPresenceRecorded;

      expect(isEnrolled, isTrue);
      expect(isBluetoothVerified, isFalse);
      expect(isPresenceRecorded, isFalse);
    });
  });

  group('MemberPresenceScreen UI Rendering Tests', () {
    testWidgets('renders Group Membership and Automatic Bluetooth Proximity sections without manual button dependency', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final authProvider = AuthProvider();
      authProvider.setMockUser(memberUser);

      // Start presence check
      await provider.startPresenceCheck(organizerId);

      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'ble-beacon-organizer-01',
          deviceName: 'HN_${provider.activeCheck!.checkToken}',
          rssi: -55,
          discoveredToken: provider.activeCheck!.checkToken,
        )
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
            ChangeNotifierProvider<SessionProvider>.value(value: provider),
          ],
          child: const MaterialApp(
            home: MemberPresenceScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(seconds: 16));
      await tester.pumpAndSettle();

      // Verify Group Membership section
      expect(find.text('Group Membership'), findsOneWidget);
      expect(find.text('✓ You are a member of this group'), findsOneWidget);

      // Verify Bluetooth Proximity section
      expect(find.text('BLUETOOTH PROXIMITY VERIFICATION'), findsOneWidget);

      // Automatically verified upon proximity detection without pressing any button
      expect(find.text('✓ Organizer detected\n✓ Bluetooth proximity verified'), findsOneWidget);
      expect(find.text('You are PRESENT'), findsOneWidget);
      expect(find.text('Automatic verification completed. No action required.'), findsOneWidget);

      provider.stopAutoPresenceScan();
    });

    test('Two-Phone Architecture: Organizer Advertises, Member Scans and Detects Beacon', () async {
      // Phone A: Organizer creates session and activates presence check -> BLE ADVERTISING ACTIVE
      await provider.startPresenceCheck(organizerId);

      expect(provider.isAdvertising, isTrue);
      expect(provider.advertiserState, equals(BleAdvertiserState.active));
      expect(BleService().advertisingServiceUuid, equals(AppConfig.bleServiceUuid));
      expect(BleService().advertisingSessionCode, equals(provider.activeSession!.joinCode));
      expect(BleService().advertisingToken, equals(provider.activeCheck!.checkToken));

      // Phone B: Member setup
      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'organizer-ble-mac-address',
          deviceName: 'HN_${provider.activeSession!.joinCode.replaceAll("HN-", "")}',
          rssi: -58,
          discoveredToken: provider.activeCheck!.checkToken,
          discoveredSessionCode: provider.activeSession!.joinCode.replaceAll("HN-", ""),
          isUuidMatch: true,
        )
      ];

      // Member verifies proximity
      final result = await provider.verifyPresence(userId: enrolledMemberId);
      expect(result, isTrue);
      expect(provider.isPresenceRecorded, isTrue);

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.present));

      // Organizer stops check
      await provider.stopOrganizerAdvertising();
      expect(provider.isAdvertising, isFalse);
      expect(provider.advertiserState, equals(BleAdvertiserState.inactive));
    });

    test('Two-Phone Architecture: Weak RSSI outside proximity threshold is rejected as outOfRange', () async {
      await provider.startPresenceCheck(organizerId);

      BleService.testBluetoothAvailable = true;
      BleService.testPermissionGranted = true;
      BleService.testDiscoveredDevices = [
        BleScanResult(
          deviceId: 'distant-organizer-device',
          deviceName: 'HN_${provider.activeSession!.joinCode.replaceAll("HN-", "")}',
          rssi: -88, // Signal too weak: -88 dBm < threshold -75 dBm
          discoveredToken: provider.activeCheck!.checkToken,
          discoveredSessionCode: provider.activeSession!.joinCode.replaceAll("HN-", ""),
          isUuidMatch: true,
        )
      ];

      final result = await provider.verifyPresence(userId: enrolledMemberId);
      expect(result, isFalse);
      expect(provider.isPresenceRecorded, isFalse);
      expect(provider.verificationStatus, equals(PresenceVerificationStatus.outOfRange));

      final member = provider.members.firstWhere((m) => m.userId == enrolledMemberId);
      expect(member.status, equals(PresenceStatus.missing));
    });
  });
}
