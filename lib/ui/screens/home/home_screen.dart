import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/state/auth_provider.dart';
import '../../../core/state/session_provider.dart';
import '../../widgets/headcount_card.dart';
import '../member/member_presence_screen.dart';
import '../organizer/organizer_dashboard_screen.dart';
import '../session_create/create_session_screen.dart';
import '../session_join/join_session_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshSessions();
    });
  }

  Future<void> _refreshSessions() async {
    if (!mounted) return;
    try {
      final auth = context.read<AuthProvider>();
      final sessionProvider = context.read<SessionProvider>();
      final user = auth.currentUser;
      if (user != null) {
        await sessionProvider.loadUserSessions(user.id);
      }
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final sessionProvider = context.watch<SessionProvider>();
    final activeSession = sessionProvider.activeSession;
    final user = auth.currentUser;

    final isOrganizer = activeSession != null && activeSession.organizerId == user?.id;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.radar_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'HereNow',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSessions,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Top Identity Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : AppColors.lightCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.accent.withAlpha(25),
                    child: Text(
                      user?.name.isNotEmpty == true ? user!.name[0].toUpperCase() : 'U',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'User',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? AppColors.darkText : AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          activeSession != null
                              ? (isOrganizer ? 'Active Role: Organizer' : 'Active Role: Member')
                              : (user?.email ?? 'Logged in'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isOrganizer ? AppColors.accent : AppColors.present,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Main Tagline
            Text(
              "Know who's here,\nwithout calling everyone.",
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1.2,
                color: isDark ? AppColors.darkText : AppColors.lightText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Temporary group presence checks via Bluetooth Low Energy.',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),

            const SizedBox(height: 24),

            // Two Core Action Buttons: Create & Join
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CreateSessionScreen(),
                        ),
                      );
                      _refreshSessions();
                    },
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                    label: const Text('Create Check'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const JoinSessionScreen(),
                        ),
                      );
                      _refreshSessions();
                    },
                    icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    label: const Text('Join Session'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      foregroundColor: isDark ? AppColors.darkText : AppColors.lightText,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 28),

            // Active Session Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ACTIVE SESSION',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                  ),
                ),
                if (activeSession != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.present.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'LIVE HEADCOUNT',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.presentDark,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            if (activeSession != null) ...[
              // Headcount card
              HeadcountCard(
                presentCount: sessionProvider.presentCount,
                totalCount: sessionProvider.totalCount,
                awayCount: sessionProvider.possiblyAwayCount,
                missingCount: sessionProvider.missingCount,
              ),

              const SizedBox(height: 12),

              // View Dashboard / Member View Button
              SizedBox(
                width: double.infinity,
                child: isOrganizer
                    ? ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const OrganizerDashboardScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.dashboard_rounded),
                        label: const Text('Open Organizer Live Dashboard'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: Colors.white,
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MemberPresenceScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: const Text('View My Member Status'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.present,
                          foregroundColor: Colors.white,
                        ),
                      ),
              ),
            ] else ...[
              // Empty State for Active Session
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.radar_outlined,
                      size: 40,
                      color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'No Active Session',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: isDark ? AppColors.darkText : AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You are not currently in an active group check. Create a check or join with a code above.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Recent Sessions
            Text(
              'RECENT SESSIONS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
              ),
            ),
            const SizedBox(height: 12),

            if (sessionProvider.userSessions.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 36,
                        color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No recent sessions',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create or join a session to see it listed here.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...sessionProvider.userSessions.map((s) {
                final sIsOrganizer = s.organizerId == user?.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () async {
                      await sessionProvider.selectSession(s.id);
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => sIsOrganizer
                                ? const OrganizerDashboardScreen()
                                : const MemberPresenceScreen(),
                          ),
                        );
                      }
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (sIsOrganizer ? AppColors.accent : AppColors.present).withAlpha(20),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              sIsOrganizer ? Icons.admin_panel_settings_rounded : Icons.groups_rounded,
                              color: sIsOrganizer ? AppColors.accent : AppColors.presentDark,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.name,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? AppColors.darkText : AppColors.lightText,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${sIsOrganizer ? "Organizer" : "Member"} • Code: ${s.joinCode}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkSubtext : AppColors.lightSubtext,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
