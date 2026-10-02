import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/config/app_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/session_member_model.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/session_provider.dart';
import '../../widgets/ble_debug_card.dart';

class MemberPresenceScreen extends StatefulWidget {
  const MemberPresenceScreen({super.key});

  @override
  State<MemberPresenceScreen> createState() => _MemberPresenceScreenState();
}

class _MemberPresenceScreenState extends State<MemberPresenceScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAutoDetection();
    });
  }

  void _initAutoDetection() {
    final authProvider = context.read<AuthProvider>();
    final sessionProvider = context.read<SessionProvider>();
    final userId = authProvider.currentUser?.id;
    if (userId != null) {
      sessionProvider.startAutoPresenceDetection(userId: userId);
    }
  }

  @override
  void dispose() {
    try {
      context.read<SessionProvider>().stopAutoPresenceScan();
    } catch (_) {}
    super.dispose();
  }

  void _confirmLeaveSession(BuildContext context) {
    final sessionProvider = context.read<SessionProvider>();
    final authProvider = context.read<AuthProvider>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave This Group Session?'),
        content: const Text(
          'You will be removed from this session. You can rejoin anytime using the join code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.missing),
            onPressed: () async {
              Navigator.pop(ctx);
              await sessionProvider.leaveSession(
                authProvider.currentUser?.id ?? 'user',
              );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('You have left the session.')),
                );
              }
            },
            child: const Text('Leave Session'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sessionProvider = context.watch<SessionProvider>();
    final authProvider = context.watch<AuthProvider>();
    final session = sessionProvider.activeSession;
    final currentUserId = authProvider.currentUser?.id;

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Presence Status')),
        body: const Center(child: Text('No active session.')),
      );
    }

    // Check membership
    final enrolledMember = sessionProvider.members.cast<SessionMemberModel?>().firstWhere(
      (m) => m != null && m.userId == currentUserId,
      orElse: () => null,
    );
    final isEnrolled = enrolledMember != null;

    final myMember = enrolledMember ?? SessionMemberModel(
      id: 'temp',
      sessionId: session.id,
      userId: currentUserId ?? 'user',
      userName: authProvider.currentUser?.name ?? 'You',
      status: PresenceStatus.missing,
      lastVerifiedAt: null,
    );

    final isPresent = myMember.status == PresenceStatus.present ||
        myMember.status == PresenceStatus.manuallyConfirmed ||
        sessionProvider.isPresenceRecorded;

    final isScanning = sessionProvider.verificationStatus == PresenceVerificationStatus.scanningForOrganizer ||
        sessionProvider.verificationStatus == PresenceVerificationStatus.checkingPrerequisites ||
        sessionProvider.verificationStatus == PresenceVerificationStatus.recordingPresence;

    final isOutOfRange = sessionProvider.verificationStatus == PresenceVerificationStatus.outOfRange && !isPresent;
    final isFailed = sessionProvider.verificationStatus == PresenceVerificationStatus.failed && !isPresent;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Presence'),
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app_rounded, color: AppColors.missing),
            tooltip: 'Leave Session',
            onPressed: () => _confirmLeaveSession(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Session Badge Card
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withAlpha(25),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          session.groupType.displayName.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'PROXIMITY: ${session.proximityMode.name.toUpperCase()}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    session.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Session Join Code: ${session.joinCode}',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 1. GROUP MEMBERSHIP CARD
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isEnrolled
                    ? (isDark ? AppColors.present.withAlpha(15) : AppColors.presentContainer.withAlpha(120))
                    : (isDark ? AppColors.missing.withAlpha(15) : AppColors.missingContainer.withAlpha(120)),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isEnrolled ? AppColors.present.withAlpha(120) : AppColors.missing.withAlpha(120),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isEnrolled ? Icons.check_circle_outline_rounded : Icons.highlight_off_rounded,
                        color: isEnrolled ? AppColors.presentDark : AppColors.missingDark,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Group Membership',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: isEnrolled ? AppColors.presentDark : AppColors.missingDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isEnrolled
                        ? '✓ You are a member of this group'
                        : '✗ You are not enrolled in this group',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isEnrolled ? AppColors.presentDark : AppColors.missingDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isEnrolled
                        ? 'Joining the group registers your device for automatic Bluetooth proximity detection. Proximity to the organizer is required to be marked present.'
                        : 'Please join the group using the join code to participate in presence checks.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkSubtext : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 2. AUTOMATIC BLUETOOTH PROXIMITY VERIFICATION CARD
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: isPresent
                    ? (isDark ? AppColors.present.withAlpha(20) : AppColors.presentContainer)
                    : isOutOfRange
                        ? (isDark ? AppColors.possiblyAway.withAlpha(20) : AppColors.possiblyAwayContainer)
                        : isFailed
                            ? (isDark ? AppColors.missing.withAlpha(25) : AppColors.missingContainer)
                            : (isDark ? AppColors.darkCard : AppColors.lightCard),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isPresent
                      ? AppColors.present
                      : isOutOfRange
                          ? AppColors.possiblyAway
                          : isFailed
                              ? AppColors.missing
                              : isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                  width: (isPresent || isFailed || isOutOfRange) ? 1.5 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  // Verification State Icon
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: isPresent
                          ? AppColors.present
                          : isOutOfRange
                              ? AppColors.possiblyAway
                              : isFailed
                                  ? AppColors.missing
                                  : isScanning
                                      ? AppColors.accent
                                      : AppColors.accent.withAlpha(30),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (isPresent
                                  ? AppColors.present
                                  : isOutOfRange
                                      ? AppColors.possiblyAway
                                      : isFailed
                                          ? AppColors.missing
                                          : AppColors.accent)
                              .withAlpha(60),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      isPresent
                          ? Icons.check_circle_rounded
                          : isOutOfRange
                              ? Icons.sensors_off_rounded
                              : isFailed
                                  ? Icons.error_outline_rounded
                                  : isScanning
                                      ? Icons.bluetooth_searching_rounded
                                      : Icons.bluetooth_rounded,
                      size: 34,
                      color: (isPresent || isFailed || isOutOfRange || isScanning)
                          ? Colors.white
                          : AppColors.accent,
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text(
                    'BLUETOOTH PROXIMITY VERIFICATION',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.accent,
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (isPresent) ...[
                    const Text(
                      '✓ Organizer detected\n✓ Bluetooth proximity verified',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        height: 1.3,
                        color: AppColors.presentDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.present.withAlpha(30),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'You are PRESENT',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.presentDark,
                        ),
                      ),
                    ),
                    if (sessionProvider.lastDetectedRssi != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Signal Strength: ${sessionProvider.lastDetectedRssi} dBm (Proximity Threshold: ${session.proximityMode.rssiThreshold} dBm)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                        ),
                      ),
                    ],
                  ] else if (isOutOfRange) ...[
                    const Text(
                      '⚠️ Organizer detected, but too far away',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.possiblyAwayDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sessionProvider.verificationError ??
                          'Signal is too weak for the configured proximity threshold. Please move closer to the organizer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Presence: Not verified',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.possiblyAwayDark,
                      ),
                    ),
                  ] else if (isFailed) ...[
                    const Text(
                      '✗ Verification issue detected',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.missingDark,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      sessionProvider.verificationError ?? 'Verification error occurred.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.missingDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Presence: Not verified',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.missingDark,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'Searching for organizer...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Bluetooth proximity: Searching...\nKeep Bluetooth turned ON and stay near the group organizer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Presence: Not verified',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.possiblyAwayDark,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Automatic Proximity Indicator (No Button Required)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isPresent
                    ? AppColors.present.withAlpha(15)
                    : (isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isPresent
                      ? AppColors.present.withAlpha(80)
                      : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isPresent
                        ? Icons.check_circle_rounded
                        : Icons.auto_mode_rounded,
                    color: isPresent ? AppColors.present : AppColors.accent,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isPresent
                          ? 'Automatic verification completed. No action required.'
                          : 'Proximity detection runs automatically. No button press required.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isPresent
                            ? AppColors.presentDark
                            : (isDark ? AppColors.darkText : AppColors.lightText),
                      ),
                    ),
                  ),
                  if (!isPresent)
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Refresh BLE scan',
                      onPressed: () {
                        if (currentUserId != null) {
                          sessionProvider.startAutoPresenceDetection(userId: currentUserId);
                        }
                      },
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // BLE DEBUG DIAGNOSTICS CARD
            BleDebugCard(
              isOrganizer: false,
              bluetoothOn: sessionProvider.isBluetoothAvailable,
              isAdvertising: false,
              isScanning: sessionProvider.isAutoScanning || isScanning,
              serviceUuid: AppConfig.bleServiceUuid,
              discoveredCount: BleService().discoveredDeviceCount,
              matchingCount: BleService().matchingDeviceCount,
              lastRssi: sessionProvider.lastDetectedRssi ?? BleService().lastDiscoveredRssi,
              rssiThreshold: session.proximityMode.rssiThreshold,
              sessionMatch: BleService().isSessionMatched,
              tokenValidation: BleService().isTokenMatched ? 'PASS' : (isPresent ? 'PASS' : 'SEARCHING'),
              proximityStatus: isPresent
                  ? 'NEAR'
                  : (isOutOfRange ? 'FAR' : (isScanning ? 'SEARCHING' : 'UNKNOWN')),
              backendStatus: isPresent
                  ? 'SUCCESS'
                  : (sessionProvider.verificationStatus == PresenceVerificationStatus.recordingPresence
                      ? 'PENDING'
                      : (isFailed ? 'FAILED' : 'WAITING')),
              isExpandedDefault: true,
            ),

            const SizedBox(height: 20),

            // 3. GRANULAR VERIFICATION SYSTEM AUDIT
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRESENCE VERIFICATION AUDIT',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildStateRow(
                    label: 'User Authenticated',
                    isOk: currentUserId != null,
                    isDark: isDark,
                  ),
                  const Divider(height: 18),
                  _buildStateRow(
                    label: 'Group Member',
                    isOk: isEnrolled,
                    isDark: isDark,
                  ),
                  const Divider(height: 18),
                  _buildStateRow(
                    label: 'Bluetooth Proximity Verified',
                    isOk: isPresent || sessionProvider.isBluetoothDeviceVerified,
                    isDark: isDark,
                  ),
                  const Divider(height: 18),
                  _buildStateRow(
                    label: 'Presence Recorded (PRESENT)',
                    isOk: isPresent,
                    isDark: isDark,
                  ),
                  if (myMember.lastVerifiedAt != null) ...[
                    const Divider(height: 18),
                    _buildDetailRow(
                      label: 'Verified Timestamp',
                      value: DateFormat('h:mm:ss a, MMM d').format(myMember.lastVerifiedAt!),
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Privacy & Architecture Notice
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.shield_outlined, size: 20, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Universal BLE Proximity Architecture',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkText : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Verification requires physical Bluetooth proximity to the organizer device. No persistent tracking or background recording is used.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStateRow({
    required String label,
    required bool isOk,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOk ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 16,
              color: isOk ? AppColors.present : (isDark ? Colors.white24 : Colors.black26),
            ),
            const SizedBox(width: 6),
            Text(
              isOk ? 'YES' : 'NO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isOk ? AppColors.presentDark : (isDark ? AppColors.darkSubtext : AppColors.lightSubtext),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkText : AppColors.lightText,
            ),
          ),
        ),
      ],
    );
  }
}
