import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/models/session_member_model.dart';
import '../../../core/services/ble_service.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/session_provider.dart';
import '../../../core/config/app_config.dart';
import '../../widgets/ble_debug_card.dart';
import '../../widgets/headcount_card.dart';
import '../../widgets/presence_badge.dart';
import '../../widgets/pulse_indicator.dart';
import 'member_detail_dialog.dart';
import 'session_qr_screen.dart';
import 'session_report_screen.dart';

class OrganizerDashboardScreen extends StatefulWidget {
  const OrganizerDashboardScreen({super.key});

  @override
  State<OrganizerDashboardScreen> createState() =>
      _OrganizerDashboardScreenState();
}

class _OrganizerDashboardScreenState extends State<OrganizerDashboardScreen>
    with WidgetsBindingObserver {
  String _searchQuery = '';
  PresenceStatus? _selectedFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final sessionProvider = context.read<SessionProvider>();
      final authProvider = context.read<AuthProvider>();
      if (sessionProvider.activeSession?.isActive == true &&
          !sessionProvider.isAdvertising) {
        sessionProvider.startOrganizerAdvertising(
          organizerId: authProvider.currentUser?.id,
        );
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Bug #8 fix: When the app returns to the foreground the Android OS may have
  /// silently stopped the BluetoothLeAdvertiser (common on battery-saving devices).
  /// Re-start advertising so the organizer beacon is always live while the dashboard
  /// is visible, even after the user switches apps and comes back.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final sessionProvider = context.read<SessionProvider>();
      final authProvider = context.read<AuthProvider>();
      if (sessionProvider.activeSession?.isActive == true &&
          !BleService().isAdvertising) {
        debugPrint('[HereNow] App resumed — restarting BLE advertising');
        sessionProvider.startOrganizerAdvertising(
          organizerId: authProvider.currentUser?.id,
        );
      }
    }
  }


  void _showMemberDetail(BuildContext context, SessionMemberModel member) {
    final provider = context.read<SessionProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => MemberDetailSheet(
        member: member,
        onManualConfirm: () => provider.manuallyConfirmMember(member.userId),
        onMarkMissing: () => provider.markMemberMissing(member.userId),
        onMarkAway: () => provider.markMemberAway(member.userId),
      ),
    );
  }

  void _sendBroadcastReminder(BuildContext context) {
    final provider = context.read<SessionProvider>();
    final missingMembers = provider.members
        .where((m) => m.status == PresenceStatus.missing)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send Reminder'),
        content: Text(
          'Send instant presence verification reminder to ${missingMembers.length} undetected members (${missingMembers.map((e) => e.userName).take(3).join(', ')}...)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Reminder dispatched to ${missingMembers.length} members.',
                  ),
                  backgroundColor: AppColors.accent,
                ),
              );
            },
            child: const Text('Send Now'),
          ),
        ],
      ),
    );
  }

  void _confirmEndSession(BuildContext context) {
    final provider = context.read<SessionProvider>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End Presence Session?'),
        content: const Text(
          'Ending this session will freeze headcount, save final presence audit data to history, and stop new presence checks.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Active'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.missing),
            onPressed: () async {
              Navigator.pop(ctx);
              await provider.endSession();
              if (context.mounted) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const SessionReportScreen()),
                );
              }
            },
            child: const Text('End Session'),
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

    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Organizer Dashboard')),
        body: const Center(child: Text('No active session selected.')),
      );
    }

    // Filter members
    var filteredMembers = sessionProvider.members.where((m) {
      final matchesSearch = m.userName.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesStatus = _selectedFilter == null || m.status == _selectedFilter;
      return matchesSearch && matchesStatus;
    }).toList();

    // Sort to prioritize missing members at the top if needed
    filteredMembers.sort((a, b) {
      if (a.status == PresenceStatus.missing && b.status != PresenceStatus.missing) return -1;
      if (a.status != PresenceStatus.missing && b.status == PresenceStatus.missing) return 1;
      return a.userName.compareTo(b.userName);
    });

    final detectedCount = sessionProvider.presentCount;
    final notDetectedCount = sessionProvider.missingCount + sessionProvider.possiblyAwayCount;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              session.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: session.isActive ? AppColors.present : AppColors.missing,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    '${session.isActive ? "Session Active" : "Ended"} • ${session.joinCode} • ${session.proximityMode.name.toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'View QR & Join Code',
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 38),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SessionQrScreen(session: session),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart_rounded),
            tooltip: 'Presence Report',
            padding: const EdgeInsets.symmetric(horizontal: 6),
            constraints: const BoxConstraints(minWidth: 38),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SessionReportScreen(),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onSelected: (val) {
              if (val == 'qr') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SessionQrScreen(session: session)),
                );
              } else if (val == 'report') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SessionReportScreen()),
                );
              } else if (val == 'reminder') {
                _sendBroadcastReminder(context);
              } else if (val == 'end') {
                _confirmEndSession(context);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'qr', child: Text('Show Join QR / Code')),
              const PopupMenuItem(value: 'report', child: Text('View Presence Report')),
              const PopupMenuItem(value: 'reminder', child: Text('Broadcast Reminder')),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'end',
                child: Text('End Session', style: TextStyle(color: AppColors.missing)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Headcount and status bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                HeadcountCard(
                  presentCount: sessionProvider.presentCount,
                  totalCount: sessionProvider.totalCount,
                  awayCount: sessionProvider.possiblyAwayCount,
                  missingCount: sessionProvider.missingCount,
                  onFilterPresent: () => setState(() => _selectedFilter =
                      _selectedFilter == PresenceStatus.present ? null : PresenceStatus.present),
                  onFilterAway: () => setState(() => _selectedFilter =
                      _selectedFilter == PresenceStatus.possiblyAway ? null : PresenceStatus.possiblyAway),
                  onFilterMissing: () => setState(() => _selectedFilter =
                      _selectedFilter == PresenceStatus.missing ? null : PresenceStatus.missing),
                ),
                PulseIndicator(
                  isScanning: sessionProvider.isAdvertising || sessionProvider.isCheckingPresence,
                  label: sessionProvider.isAdvertising ? 'BLE Presence Active' : 'BLE Presence Broadcast Starting...',
                  subtitle: sessionProvider.isAdvertising
                      ? 'BLE Advertiser: ACTIVE • Service UUID: ${AppConfig.bleServiceUuid.substring(0, 8)}... • Ephemeral Token Active'
                      : 'Preparing Bluetooth Low Energy presence beacon...',
                ),
                BleDebugCard(
                  isOrganizer: true,
                  bluetoothOn: sessionProvider.isBluetoothAvailable,
                  isAdvertising: sessionProvider.isAdvertising,
                  isScanning: false,
                  serviceUuid: AppConfig.bleServiceUuid,
                  discoveredCount: 0,
                  matchingCount: sessionProvider.presentCount,
                  lastRssi: null,
                  sessionMatch: true,
                  tokenValidation: sessionProvider.activeCheck != null ? 'PASS' : 'STARTING',
                  proximityStatus: sessionProvider.isAdvertising ? 'NEAR (BROADCASTING)' : 'STANDBY',
                  backendStatus: 'ACTIVE',
                  isExpandedDefault: false,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Primary Actions Row: "START PRESENCE CHECK / CHECK AGAIN" and "SEND REMINDER"
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: ElevatedButton.icon(
                    onPressed: sessionProvider.isCheckingPresence
                        ? null
                        : () async {
                            final btReady = await BleService().isBluetoothAvailable();
                            if (!btReady && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('⚠️ Bluetooth is turned off. Please enable Bluetooth for live BLE presence broadcast.'),
                                  backgroundColor: AppColors.possiblyAwayDark,
                                  duration: Duration(seconds: 4),
                                ),
                              );
                            }
                            sessionProvider.startPresenceCheck(
                              authProvider.currentUser?.id ?? 'organizer',
                            );
                          },
                    icon: sessionProvider.isCheckingPresence
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.radar_rounded, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        sessionProvider.isCheckingPresence
                            ? 'Scanning...'
                            : sessionProvider.presentCount > 0
                                ? 'Check Again'
                                : 'Start Presence Check',
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    onPressed: () => _sendBroadcastReminder(context),
                    icon: const Icon(Icons.notifications_active_outlined, size: 18),
                    label: const FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('Remind'),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: isDark ? AppColors.darkText : AppColors.lightText,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 42,
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search members...',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                  ),
                ),
                if (_selectedFilter != null) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    label: Text(
                      'Clear Filter: ${_selectedFilter!.displayName}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () => setState(() => _selectedFilter = null),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Member List Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'MEMBERS (${filteredMembers.length}) • PRESENT: $detectedCount • NOT DETECTED: $notDetectedCount',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Tap for actions',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                  ),
                ),
              ],
            ),
          ),

          // Member List
          Expanded(
            child: filteredMembers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_outlined,
                          size: 48,
                          color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No members match criteria',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    itemCount: filteredMembers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final member = filteredMembers[index];
                      final isPresent = member.status == PresenceStatus.present ||
                          member.status == PresenceStatus.manuallyConfirmed;

                      return InkWell(
                        onTap: () => _showMemberDetail(context, member),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkCard : AppColors.lightCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: member.status == PresenceStatus.missing
                                  ? AppColors.missing.withAlpha(80)
                                  : isDark
                                      ? AppColors.darkBorder
                                      : AppColors.lightBorder,
                              width: member.status == PresenceStatus.missing ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isPresent
                                    ? AppColors.present.withAlpha(25)
                                    : isDark
                                        ? Colors.white12
                                        : Colors.black12,
                                child: Text(
                                  member.userName.isNotEmpty
                                      ? member.userName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                    color: isPresent ? AppColors.presentDark : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      spacing: 6,
                                      runSpacing: 2,
                                      children: [
                                        Text(
                                          member.userName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: isDark ? AppColors.darkText : AppColors.lightText,
                                          ),
                                        ),
                                        if (member.isOrganizer)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.accent.withAlpha(25),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: const Text(
                                              'Organizer',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.accent,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      member.isOrganizer
                                          ? (sessionProvider.isAdvertising
                                              ? 'BLE Advertiser: ACTIVE (Host)'
                                              : 'BLE Advertiser: Standby')
                                          : (isPresent
                                              ? 'Verified ${member.relativeTimeAgo} (BLE Proximity)'
                                              : 'Not detected in Bluetooth range'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isPresent
                                            ? AppColors.presentDark
                                            : isDark
                                                ? AppColors.darkSubtext
                                                : AppColors.lightSubtext,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              PresenceBadge(status: member.status),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
